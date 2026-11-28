import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models.dart';
import '../services/core_services.dart';
import '../store/app_store.dart';
import 'chat_screen.dart';

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
  const AddMemberScreen({
    super.key,
    required this.store,
    this.initialGroupId,
    this.initialTab = 0,
  });

  final AppStore store;
  final String? initialGroupId;
  final int initialTab;

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
    _selectedGroupId = widget.initialGroupId;
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
    final groupLabel = _selectedGroupId == null
        ? '連絡先のみ'
        : (widget.store.findGroup(_selectedGroupId!)?.name ?? '選択グループ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${added.name}（${added.inviteId}）」を追加しました（$groupLabel）'),
      ),
    );
    _idCtrl.clear();
    _nameCtrl.clear();
    setState(() {});
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

  Future<void> _confirmDeleteContact(MemberProfile contact) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dc) => AlertDialog(
        title: const Text('連絡先を削除'),
        content: Text(
          '「${contact.name}（${contact.inviteId}）」を友だち一覧から削除しますか？\n'
          '※ 既存のグループから外したい場合は、各トーク画面右上のメンバー管理から削除してください。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dc).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dc).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.removeContact(contact.inviteId);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${contact.name}」を削除しました')),
        );
      }
    }
  }

  Future<void> _pickGroupForContact(MemberProfile contact) async {
    if (widget.store.groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('追加できるグループがまだありません')),
      );
      return;
    }
    final groupId = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext bc) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              title: Text(
                '「${contact.name}」を追加するグループを選択',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final g in widget.store.groups)
              ListTile(
                leading: CircleAvatar(child: Text(initialLetter(g.category))),
                title: Text(g.name),
                subtitle: Text('${g.members.length}人'),
                onTap: () => Navigator.of(bc).pop(g.id),
              ),
          ],
        ),
      ),
    );
    if (groupId != null) {
      await widget.store.addContactToGroup(groupId, contact);
      if (mounted) {
        final gName = widget.store.findGroup(groupId)?.name ?? 'グループ';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${contact.name}」を $gName に追加しました')),
        );
      }
    }
  }

  Future<void> _openDirectChat(MemberProfile contact) async {
    final g = await widget.store.openOrCreateDirectChat(contact);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(store: widget.store, groupId: g.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeInitialTab = widget.initialTab.clamp(0, 3);
    return DefaultTabController(
      length: 4,
      initialIndex: safeInitialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('友だち追加・連絡先管理'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(icon: Icon(Icons.qr_code), text: '自分のQR'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR読取'),
              Tab(icon: Icon(Icons.person_add), text: 'IDで追加'),
              Tab(icon: Icon(Icons.people), text: '友だち一覧'),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: widget.store,
          builder: (_, __) => TabBarView(
            children: <Widget>[
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '相手に表示される名前: ${widget.store.myName}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final ctrl = TextEditingController(text: widget.store.myName);
                          try {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext dc) => AlertDialog(
                                title: const Text('相手に表示される名前を変更'),
                                content: TextField(
                                  controller: ctrl,
                                  decoration: const InputDecoration(
                                    labelText: '表示名',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.of(dc).pop(false),
                                    child: const Text('キャンセル'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(dc).pop(true),
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && ctrl.text.trim().isNotEmpty) {
                              await widget.store.updateMyDisplayName(ctrl.text);
                              if (mounted) setState(() {});
                            }
                          } finally {
                            disposeControllersSafely(<ChangeNotifier>[ctrl]);
                          }
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('表示名を変更'),
                      ),
                      const SizedBox(height: 10),
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
                ],
              ),
              widget.store.contacts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'まだ登録された友だちはいません。\n「QR読取」または「IDで追加」タブから個人を登録できます。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: widget.store.contacts.length,
                      itemBuilder: (_, int i) {
                        final c = widget.store.contacts[i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFE8F5E9),
                              foregroundColor: const Color(0xFF1B8A5A),
                              child: Text(initialLetter(c.name)),
                            ),
                            title: Text(
                              c.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('ID: ${c.inviteId}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  tooltip: '1対1トーク',
                                  icon: const Icon(Icons.chat_bubble_outline,
                                      color: Color(0xFF1B8A5A)),
                                  onPressed: () => _openDirectChat(c),
                                ),
                                IconButton(
                                  tooltip: 'グループへ追加',
                                  icon: const Icon(Icons.group_add_outlined),
                                  onPressed: () => _pickGroupForContact(c),
                                ),
                                IconButton(
                                  tooltip: '削除',
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _confirmDeleteContact(c),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSelector() {
    return Card(
      color: const Color(0xFFF3F6F4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '追加先グループ（任意）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('追加しない（連絡先のみ）'),
                  selected: _selectedGroupId == null,
                  onSelected: (_) => setState(() => _selectedGroupId = null),
                ),
                for (final g in widget.store.groups)
                  ChoiceChip(
                    label: Text(g.name),
                    selected: _selectedGroupId == g.id,
                    onSelected: (_) => setState(() => _selectedGroupId = g.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
