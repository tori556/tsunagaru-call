import 'dart:async';
import 'dart:convert';
 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
 
import '../models.dart';
import '../services/core_services.dart';
import '../store/app_store.dart';
 
class LockOverlayScreen extends StatefulWidget {
  const LockOverlayScreen({super.key, required this.store});
  final AppStore store;
 
  @override
  State<LockOverlayScreen> createState() => _LockOverlayScreenState();
}
 
class _LockOverlayScreenState extends State<LockOverlayScreen> {
  final TextEditingController _pinCtrl = TextEditingController();
  int _failCount = 0;
  int _cooldownSec = 0;
  Timer? _cooldownTimer;
  String? _errorMsg;
 
  @override
  void initState() {
    super.initState();
    if (widget.store.useBiometrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }
 
  Future<void> _tryBiometric() async {
    if (_cooldownSec > 0) return;
    final ok = await AuthLockService.authenticateBiometric();
    if (ok && mounted) {
      widget.store.unlockApp();
    }
  }
 
  Future<void> _verifyPin() async {
    if (_cooldownSec > 0) return;
    final ok = await AuthLockService.verifyPin(_pinCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      _pinCtrl.clear();
      widget.store.unlockApp();
    } else {
      _failCount++;
      _pinCtrl.clear();
      if (_failCount >= 5) {
        _failCount = 0;
        _startCooldown(30);
      } else {
        setState(() => _errorMsg = '暗証番号が違います（$_failCount/5回失敗）');
      }
    }
  }
 
  Future<void> _confirmForgotPin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dc) => AlertDialog(
        title: const Text('暗証番号を忘れた場合'),
        content: const Text(
          '端末の生体認証（または確認操作）を行ったうえで、アプリロック設定を初期化します。\n'
          'トーク履歴やグループ設定はそのまま保持されます。\n\nロックを初期化しますか？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dc).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dc).pop(true),
            child: const Text('ロックを初期化'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
 
    if (await AuthLockService.canUseBiometrics()) {
      final bioOk = await AuthLockService.authenticateBiometric();
      if (!bioOk) {
        if (mounted) {
          setState(() => _errorMsg = '初期化には端末の生体認証確認が必要です');
        }
        return;
      }
    }
    await widget.store.resetLockEmergency();
  }
 
  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSec = seconds;
      _errorMsg = '5回失敗したため $seconds 秒間ロックされました';
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldownSec <= 1) {
        t.cancel();
        setState(() {
          _cooldownSec = 0;
          _errorMsg = null;
        });
      } else {
        setState(() {
          _cooldownSec--;
          _errorMsg = 'あと $_cooldownSec 秒待ってから再試行してください';
        });
      }
    });
  }
 
  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pinCtrl.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.lock_outline, size: 56, color: Color(0xFF1B8A5A)),
                const SizedBox(height: 12),
                const Text(
                  'trancefer ロック中',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  enabled: _cooldownSec == 0,
                  decoration: const InputDecoration(
                    labelText: '暗証番号 / パスワードを入力',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _verifyPin(),
                ),
                if (_errorMsg != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _cooldownSec == 0 ? _verifyPin : null,
                    child: const Text('ロック解除'),
                  ),
                ),
                if (widget.store.useBiometrics) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _cooldownSec == 0 ? _tryBiometric : null,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('指紋・顔認証で解除'),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cooldownSec == 0 ? _confirmForgotPin : null,
                  child: const Text('暗証番号を忘れた場合'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
 
class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({super.key, required this.store});
  final AppStore store;
 
  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}
 
class _AddMemberScreenState extends State<AddMemberScreen> {
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _selectedGroupId;
  bool _scanHandled = false;
 
  @override
  void initState() {
    super.initState();
    if (widget.store.groups.isNotEmpty) {
      _selectedGroupId = widget.store.groups.first.id;
    }
  }
 
  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }
 
  String get _myQrPayload => jsonEncode(<String, String>{
        'app': 'tsunagaru_call',
        'id': widget.store.myInviteId,
        'name': widget.store.myName,
      });
 
  Future<void> _submitId(String rawId, {String? name}) async {
    final id = rawId.trim();
    if (id.isEmpty) return;
    final added = await widget.store.addContactByIdOrQr(
      inviteId: id,
      fallbackName: name,
      targetGroupId: _selectedGroupId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「${added.name}（${added.inviteId}）」を追加しました')),
    );
    _idCtrl.clear();
    _nameCtrl.clear();
  }
 
  void _onQrDetected(BarcodeCapture capture) {
    if (_scanHandled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _scanHandled = true;
      String parsedId = raw;
      String? parsedName;
      try {
        final map = jsonDecode(raw) as JsonMap;
        if (map['id'] != null) parsedId = map['id'].toString();
        if (map['name'] != null) parsedName = map['name'].toString();
      } catch (_) {}
      _submitId(parsedId, name: parsedName).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('QR・IDで友だち追加'),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(icon: Icon(Icons.qr_code), text: '自分のQR'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR読取'),
              Tab(icon: Icon(Icons.search), text: 'ID検索'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.store.myName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: QrImageView(
                          data: _myQrPayload,
                          version: QrVersions.auto,
                          size: 200,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      '招待ID: ${widget.store.myInviteId}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.store.myInviteId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('招待IDをコピーしました')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('招待IDをコピー'),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildGroupSelector(),
                ),
                Expanded(
                  child: MobileScanner(onDetect: _onQrDetected),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('相手のQRコードをカメラ枠に写すと自動追加します'),
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _buildGroupSelector(),
                const SizedBox(height: 12),
                TextField(
                  controller: _idCtrl,
                  decoration: const InputDecoration(
                    labelText: '相手の招待ID（例：TSU-8492-K）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '表示名メモ（ローカル追加時の名前・任意）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () =>
                      _submitId(_idCtrl.text, name: _nameCtrl.text),
                  icon: const Icon(Icons.person_add),
                  label: const Text('IDで検索して追加'),
                ),
                const SizedBox(height: 20),
                const Text(
                  '追加済みメンバー一覧',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (widget.store.contacts.isEmpty)
                  const Text('まだ追加されたメンバーはありません。')
                else
                  for (final c in widget.store.contacts)
                    ListTile(
                      leading: CircleAvatar(child: Text(initialLetter(c.name))),
                      title: Text(c.name),
                      subtitle: Text('ID: ${c.inviteId}'),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildGroupSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const Text('追加先グループ: '),
        for (final g in widget.store.groups)
          ChoiceChip(
            label: Text(g.name),
            selected: _selectedGroupId == g.id,
            onSelected: (_) => setState(() => _selectedGroupId = g.id),
          ),
      ],
    );
  }
}
