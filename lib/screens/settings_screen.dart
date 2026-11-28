import 'package:flutter/material.dart';
 
import '../models.dart';
import '../services/core_services.dart';
import '../store/app_store.dart';
import 'lock_and_qr_screens.dart';
 
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.store});
  final AppStore store;
 
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}
 
class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _nameCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _tokenCtrl;
 
  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.store.myName);
    _urlCtrl = TextEditingController(text: widget.store.liveKitUrl);
    _tokenCtrl = TextEditingController(text: widget.store.liveKitToken);
  }
 
  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }
 
  Future<void> _configurePin() async {
    final pinCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext dc) => AlertDialog(
          title: const Text('暗証番号 / パスワードを設定'),
          content: TextField(
            controller: pinCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '4〜8桁の暗証番号を入力',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dc).pop(false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.of(dc).pop(true), child: const Text('保存')),
          ],
        ),
      );
      if (ok == true && pinCtrl.text.trim().length >= 4) {
        await AuthLockService.savePin(pinCtrl.text.trim());
        widget.store.lockEnabled = true;
        await widget.store.saveImmediate();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('アプリロックを有効化しました')),
          );
        }
      }
    } finally {
      disposeControllersSafely(<ChangeNotifier>[pinCtrl]);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        Card(
          child: ListTile(
            leading: const Icon(Icons.qr_code_2, color: Color(0xFF1B8A5A), size: 32),
            title: Text('自分の招待ID: ${s.myInviteId}'),
            subtitle: const Text('QRコード表示・カメラ読取・ID検索で友だち追加'),
            trailing: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => AddMemberScreen(store: s)),
              ),
              child: const Text('開く'),
            ),
          ),
        ),
        const SizedBox(height: 12),
 
        const Text('メッセージ自動消去の既定設定',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: expireChoices
                  .map(
                    (int h) => ChoiceChip(
                      label: Text(formatExpireLabel(h)),
                      selected: s.defaultExpireHours == h,
                      onSelected: (_) {
                        s.defaultExpireHours = h;
                        s.save(syncProfile: true);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
 
        const Text('セキュリティロック（指紋・暗証番号）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                title: const Text('起動・復帰時にロックを要求'),
                subtitle: Text('バックグラウンド復帰猶予: ${s.lockGraceSeconds}秒'),
                value: s.lockEnabled,
                onChanged: (bool v) async {
                  if (v && !await AuthLockService.hasPin()) {
                    await _configurePin();
                  } else {
                    s.lockEnabled = v;
                    await s.saveImmediate();
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(
                  spacing: 8,
                  children: const <int>[0, 30, 60]
                      .map(
                        (int sec) => ChoiceChip(
                          label: Text(sec == 0 ? '即時ロック' : '$sec秒後'),
                          selected: s.lockGraceSeconds == sec,
                          onSelected: (_) {
                            s.lockGraceSeconds = sec;
                            s.save();
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              SwitchListTile(
                title: const Text('指紋・顔認証を優先使用'),
                value: s.useBiometrics,
                onChanged: (bool v) {
                  s.useBiometrics = v;
                  s.save();
                },
              ),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('暗証番号を変更'),
                trailing: OutlinedButton(
                  onPressed: _configurePin,
                  child: const Text('設定'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
 
        const Text('通信ガード・プライバシー設定',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                title: const Text('Wi-Fi以外で確認ポップアップを表示'),
                subtitle: const Text('ビデオ通話・大容量ファイル送信・APK更新の前に確認'),
                value: s.warnOnNonWifi,
                onChanged: (bool v) {
                  s.warnOnNonWifi = v;
                  s.save();
                },
              ),
              SwitchListTile(
                title: const Text('オンライン状態を公開'),
                value: s.showOnlineStatus,
                onChanged: (bool v) {
                  s.showOnlineStatus = v;
                  s.save(syncProfile: true);
                },
              ),
              SwitchListTile(
                title: const Text('最終接続時刻を公開'),
                value: s.showLastSeen,
                onChanged: (bool v) {
                  s.showLastSeen = v;
                  s.save(syncProfile: true);
                },
              ),
              SwitchListTile(
                title: const Text('入力中表示を共有'),
                value: s.shareTypingStatus,
                onChanged: (bool v) {
                  s.shareTypingStatus = v;
                  s.save(syncProfile: true);
                },
              ),
              SwitchListTile(
                title: const Text('通話時のノイズキャンセリング'),
                value: s.noiseCancellationEnabled,
                onChanged: (bool v) {
                  s.noiseCancellationEnabled = v;
                  s.save();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
 
        const Text('Firebase クラウド同期・着信通知テスト',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: Icon(
                  s.cloud.isReady ? Icons.cloud_done : Icons.cloud_off,
                  color: s.cloud.isReady ? Colors.green : Colors.orange,
                ),
                title: Text(s.cloud.statusLabel),
                subtitle: Text(
                  s.cloud.isReady
                      ? 'UID: ${s.cloud.uid ?? "-"} ／ リアルタイム双方向同期中'
                      : 'google-services.json 導入後は自動で同期・着信通知が有効化',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.ring_volume),
                title: const Text('着信通知・着信画面を今すぐ試す'),
                trailing: FilledButton.tonal(
                  onPressed: s.triggerTestIncomingCall,
                  child: const Text('着信テスト'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
 
        const Text('プロフィール・LiveKit通話接続',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '自分の表示名')),
                TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: 'LiveKit サーバーURL（wss://...）')),
                TextField(controller: _tokenCtrl, decoration: const InputDecoration(labelText: 'LiveKit 接続トークン')),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      s.myName = _nameCtrl.text.trim().isEmpty ? '自分' : _nameCtrl.text.trim();
                      s.liveKitUrl = _urlCtrl.text.trim();
                      s.liveKitToken = _tokenCtrl.text.trim();
                      s.saveImmediate(syncProfile: true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('設定を保存しました')),
                      );
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
 
        Card(
          child: ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: Text('アプリ更新を確認（Build #$appBuildNumberStr）'),
            subtitle: Text(githubRepo.isEmpty ? 'ローカルビルド' : 'リポジトリ: $githubRepo'),
            trailing: OutlinedButton(
              onPressed: () async {
                final info = await UpdateChecker.checkLatest();
                if (!context.mounted) return;
                if (info == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('現在のバージョンが最新です')),
                  );
                } else {
                  s.pendingUpdate = info;
                  s.save();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('最新版 ${info.versionName} が見つかりました')),
                  );
                }
              },
              child: const Text('確認'),
            ),
          ),
        ),
      ],
    );
  }
}
