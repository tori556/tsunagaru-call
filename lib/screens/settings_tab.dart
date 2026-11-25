import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/push_callkit_incoming.dart';
import 'qr_friend_screen.dart';
import 'ringtone_settings_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  void _editProfileDialog(BuildContext context) {
    final fb = FirebaseService.instance;
    final me = fb.currentUser;
    if (me == null) return;

    final nameCtrl = TextEditingController(text: me.displayName);
    final statusCtrl = TextEditingController(text: me.statusMessage);
    String emoji = me.emoji;
    const emojis = ['👨', '👩', '🧒', '👧', '👵', '👴', '🧑', '👨‍💼', '👩‍💼', '😊'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('プロフィール編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '表示名'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: statusCtrl,
                  decoration: const InputDecoration(labelText: 'ひとことステータス'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: emojis
                      .map((em) => ChoiceChip(
                            label: Text(em, style: const TextStyle(fontSize: 18)),
                            selected: emoji == em,
                            onSelected: (_) => setDlg(() => emoji = em),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () async {
                await fb.updateProfile(
                  displayName: nameCtrl.text.trim().isEmpty
                      ? me.displayName
                      : nameCtrl.text.trim(),
                  emoji: emoji,
                  statusMessage: statusCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _accountDialog(BuildContext context, {required bool isSignIn}) {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSignIn ? 'アカウント復元ログイン' : '機種変更用のメール連携'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSignIn
                  ? '以前連携したメールアドレスでログインすると連絡先やグループが復元されます。'
                  : 'メールアドレスを連携しておくと、スマホを機種変更してもデータを引き継げます。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'メールアドレス'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'パスワード（6文字以上）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              final err = isSignIn
                  ? await FirebaseService.instance.signInWithEmail(
                      email: emailCtrl.text,
                      password: passCtrl.text,
                    )
                  : await FirebaseService.instance.linkEmailAccount(
                      email: emailCtrl.text,
                      password: passCtrl.text,
                    );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(err ?? (isSignIn ? 'ログインしました' : 'アカウントを連携しました')),
                ),
              );
            },
            child: Text(isSignIn ? 'ログイン' : '連携する'),
          ),
        ],
      ),
    );
  }

  void _liveKitDialog(BuildContext context) {
    final fb = FirebaseService.instance;
    final urlCtrl = TextEditingController(text: fb.liveKitUrl);
    final epCtrl = TextEditingController(text: fb.liveKitTokenEndpoint);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('グループ通話（LiveKit SFU）設定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LiveKit Cloud の wss URL と Cloud Functions `issueLiveKitToken` のURLを設定します。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'LiveKit WebSocket URL',
                  hintText: 'wss://your-project.livekit.cloud',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: epCtrl,
                decoration: const InputDecoration(
                  labelText: 'トークン発行 Function URL',
                  hintText: 'https://asia-northeast1-xxx.cloudfunctions.net/issueLiveKitToken',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              await fb.saveLiveKitConfig(
                url: urlCtrl.text,
                tokenEndpoint: epCtrl.text,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('LiveKit設定を保存しました')),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _turnDialog(BuildContext context) {
    final fb = FirebaseService.instance;
    final epCtrl = TextEditingController(text: fb.turnEndpointUrl);
    final urlCtrl = TextEditingController(text: fb.manualTurnUrl);
    final userCtrl = TextEditingController(text: fb.manualTurnUser);
    final passCtrl = TextEditingController(text: fb.manualTurnPass);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('携帯回線用 TURN サーバー連携'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '4G/5G回線とWi-Fi間でも安定して通話するため、Cloud Functions `issueTurnCredentials` URL（自動取得）または手動TURN情報を設定できます。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: epCtrl,
                decoration: const InputDecoration(
                  labelText: '自動取得 Function URL（推奨）',
                  hintText: 'https://asia-northeast1-xxx.cloudfunctions.net/issueTurnCredentials',
                ),
              ),
              const SizedBox(height: 10),
              const Divider(),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: '手動 TURN URL（任意）',
                  hintText: 'turn:relay.example.com:3478',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: 'ユーザー名'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'パスワード / クレデンシャル'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              await fb.saveTurnConfig(
                endpointUrl: epCtrl.text,
                turnUrl: urlCtrl.text,
                username: userCtrl.text,
                credential: passCtrl.text,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('TURNサーバー設定を保存しました')),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb = FirebaseService.instance;
    final me = fb.currentUser;
    final fcm = PushCallKitService.instance.fcmToken;
    final voip = PushCallKitService.instance.voipToken ?? me?.voipToken;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('プロフィールを編集'),
                subtitle: Text('${me?.emoji ?? ''} ${me?.displayName ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editProfileDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.music_note_outlined, color: Color(0xFFF97316)),
                title: const Text('カテゴリ別の着信音・バイブ設定'),
                subtitle: const Text('家族・友達・仕事・親戚・その他を個別に設定'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RingtoneSettingsScreen(),
                  ));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('マイQRコードを表示・読み取り'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const QrFriendScreen(),
                  ));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('マイIDをコピー'),
                subtitle: Text(me?.myId ?? ''),
                trailing: const Icon(Icons.copy, size: 18),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: me?.myId ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('マイIDをコピーしました')),
                  );
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.format_size),
                title: const Text('文字をおおきめ表示（見やすく）'),
                value: fb.largeFont,
                onChanged: (_) => fb.toggleLargeFont(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.router_outlined),
                title: const Text('携帯回線用 TURN サーバー連携'),
                subtitle: Text(
                  fb.isTurnConfigured
                      ? '✅ 設定済（4G/5G・厳格NAT中継有効）'
                      : '未設定（STUN直接接続モード）',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _turnDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('グループ通話（LiveKit SFU）設定'),
                subtitle: Text(
                  fb.isLiveKitConfigured
                      ? '✅ 設定済（本番SFU接続）'
                      : '未設定（デモグリッド動作中）',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _liveKitDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('機種変更用のメールアカウント連携'),
                subtitle: Text(
                  (me?.email != null && me!.email!.isNotEmpty)
                      ? '連携済: ${me.email}'
                      : '未連携（匿名利用中）',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _accountDialog(context, isSignIn: false),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('既存アカウントでログイン（データ復元）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _accountDialog(context, isSignIn: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🚀 Phase 4 本番通信・着信ステータス',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  fb.firebaseReady
                      ? '✅ Firebase 本番接続中（Firestore / Storage / FCM）'
                      : '🧪 デモモード動作中（flutterfire configure 後に本番接続）',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: fb.firebaseReady
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'FCMトークン: ${fcm != null && fcm.isNotEmpty ? '${fcm.substring(0, fcm.length > 20 ? 20 : fcm.length)}…' : '未取得'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                Text(
                  'iOS PushKit VoIPトークン: ${voip != null && voip.isNotEmpty ? '${voip.substring(0, voip.length > 20 ? 20 : voip.length)}…（有効）' : '未取得（iOS実機・TestFlightで自動取得）'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
