import 'dart:async';
import 'dart:ui';
 
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
 
import 'models.dart';
import 'screens/call_screens.dart';
import 'screens/chat_screen.dart';
import 'screens/lock_and_qr_screens.dart';
import 'screens/phone_dialer_screen.dart';
import 'screens/settings_screen.dart';
import 'services/cloud_sync_service.dart';
import 'services/core_services.dart';
import 'store/app_store.dart';
 
void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
 
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (_) {}
 
      FlutterError.onError = (FlutterErrorDetails details) {
        ErrorGuard.record(
          'UIエラーを吸収: ${details.exceptionAsString()}',
          details.stack,
        );
      };
 
      PlatformDispatcher.instance.onError = (dynamic error, StackTrace stack) {
        ErrorGuard.record('システムエラーを吸収: $error', stack);
        return true;
      };
 
      ErrorWidget.builder = (FlutterErrorDetails details) {
        ErrorGuard.record(
          '描画エラーを安全スキップ: ${details.exceptionAsString()}',
          details.stack,
        );
        return const SizedBox.shrink();
      };
 
      runApp(const TsunagaruCallApp());
    },
    (dynamic error, StackTrace stack) {
      ErrorGuard.record('非同期エラーを吸収: $error', stack);
    },
  );
}
 
class TsunagaruCallApp extends StatefulWidget {
  const TsunagaruCallApp({super.key});
 
  @override
  State<TsunagaruCallApp> createState() => _TsunagaruCallAppState();
}
 
class _TsunagaruCallAppState extends State<TsunagaruCallApp>
    with WidgetsBindingObserver {
  final AppStore _store = AppStore();
 
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.init();
  }
 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _store.handleAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      _store.handleAppResumed();
    }
  }
 
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'trancefer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B8A5A)),
        useMaterial3: true,
      ),
      home: AnimatedBuilder(
        animation: _store,
        builder: (BuildContext context, _) {
          if (_store.lockEnabled && !_store.isUnlocked) {
            return LockOverlayScreen(store: _store);
          }
 
          if (_store.activeIncomingCall != null) {
            final call = _store.activeIncomingCall!;
            return IncomingCallScreen(
              store: _store,
              payload: call,
              onAccept: (bool withVideo) {
                final group = _store.findGroup(call.groupId) ??
                    (_store.groups.isNotEmpty
                        ? _store.groups.first
                        : ChatGroup(
                            id: call.groupId,
                            name: call.groupName,
                            category: '個人',
                            members: <String>[_store.myName, call.callerName],
                          ));
                _store.clearIncomingCall(status: 'active');
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => CallScreen(
                      store: _store,
                      group: group,
                      initialVideo: withVideo,
                      callId: call.callId,
                    ),
                  ),
                );
              },
            );
          }
 
          return MainShell(store: _store);
        },
      ),
    );
  }
}
 
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.store});
  final AppStore store;
 
  @override
  State<MainShell> createState() => _MainShellState();
}
 
class _MainShellState extends State<MainShell> {
  int _tabIndex = 0;
  String _selectedCategory = 'すべて';
  List<ConnectivityResult> _connectivity = const <ConnectivityResult>[
    ConnectivityResult.none,
  ];
  StreamSubscription<List<ConnectivityResult>>? _connSub;
 
  @override
  void initState() {
    super.initState();
    _initConn();
  }
 
  Future<void> _initConn() async {
    try {
      final res = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _connectivity = res);
      _connSub = Connectivity().onConnectivityChanged.listen(
        (List<ConnectivityResult> r) {
          if (mounted) setState(() => _connectivity = r);
        },
        onError: (dynamic e, StackTrace s) => ErrorGuard.record('回線監視: $e', s),
      );
    } catch (e, s) {
      ErrorGuard.record('回線初期化: $e', s);
    }
  }
 
  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
 
  Future<void> _startGroupCall(ChatGroup group, {required bool video}) async {
    if (video) {
      final ok = await NetworkGuard.confirmIfNotWifi(
        context,
        actionName: '${group.name} のビデオ通話',
        warnOnNonWifi: widget.store.warnOnNonWifi,
      );
      if (!ok || !mounted) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          store: widget.store,
          group: group,
          initialVideo: video,
        ),
      ),
    );
  }
 
  Future<void> _openCreateGroupDialog() async {
    final nameCtrl = TextEditingController();
    final membersCtrl = TextEditingController();
    var category = '家族';
 
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext dc) => StatefulBuilder(
          builder: (BuildContext _, StateSetter setLocal) => AlertDialog(
            title: const Text('新しいグループを作成'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'グループ名')),
                const SizedBox(height: 10),
                const Text('分類'),
                Wrap(
                  spacing: 8,
                  children: const <String>['家族', '親戚', '仕事']
                      .map(
                        (String c) => ChoiceChip(
                          label: Text(c),
                          selected: category == c,
                          onSelected: (_) => setLocal(() => category = c),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: membersCtrl,
                  decoration: const InputDecoration(labelText: 'メンバー（カンマ区切り・空欄でも作成可）'),
                ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.of(dc).pop(false), child: const Text('キャンセル')),
              FilledButton(onPressed: () => Navigator.of(dc).pop(true), child: const Text('作成')),
            ],
          ),
        ),
      );
 
      if (ok == true && nameCtrl.text.trim().isNotEmpty) {
        final members = membersCtrl.text
            .split(RegExp(r'[,、]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        await widget.store.addGroup(nameCtrl.text.trim(), category, members);
      }
    } finally {
      disposeControllersSafely(<ChangeNotifier>[nameCtrl, membersCtrl]);
    }
  }
 
  Future<void> _openRenameGroupDialog(ChatGroup group) async {
    final ctrl = TextEditingController(text: group.name);
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (BuildContext dc) => AlertDialog(
          title: const Text('グループ名を変更'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: ctrl,
                decoration: const InputDecoration(
                  labelText: '新しいグループ名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => Navigator.of(dc).pop('delete'),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('このグループを削除'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dc).pop(null),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dc).pop('rename'),
              child: const Text('変更を保存'),
            ),
          ],
        ),
      );
      if (action == 'rename' && ctrl.text.trim().isNotEmpty) {
        final nextName = ctrl.text.trim();
        await widget.store.renameGroup(group.id, nextName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('グループ名を「$nextName」に変更しました')),
          );
        }
      } else if (action == 'delete' && mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (BuildContext dc) => AlertDialog(
            title: const Text('グループを削除'),
            content: Text('「${group.name}」を一覧から削除しますか？'),
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
        if (confirm == true) {
          await widget.store.deleteGroup(group.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('「${group.name}」を削除しました')),
            );
          }
        }
      }
    } finally {
      disposeControllersSafely(<ChangeNotifier>[ctrl]);
    }
  }

  void _showErrorLogs() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dc) => AlertDialog(
        title: const Text('安全ガード 記録ログ'),
        content: SizedBox(
          width: double.maxFinite,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: ErrorGuard.logs,
            builder: (_, List<String> entries, __) {
              if (entries.isEmpty) {
                return const Text('エラー記録はありません。正常動作中です。');
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 8),
                itemBuilder: (_, int i) =>
                    Text(entries[i], style: const TextStyle(fontSize: 12)),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              ErrorGuard.clear();
              Navigator.of(dc).pop();
            },
            child: const Text('消去'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dc).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _buildTalkTab(),
      _buildCallTab(),
      SettingsTab(store: widget.store),
    ];
 
    return Scaffold(
      appBar: AppBar(
        title: const Text('trancefer'),
        actions: <Widget>[
          IconButton(
            tooltip: 'QR・IDで友だち追加',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AddMemberScreen(store: widget.store),
              ),
            ),
          ),
          IconButton(
            tooltip: '安全ガードログ',
            icon: const Icon(Icons.shield_outlined),
            onPressed: _showErrorLogs,
          ),
        ],
      ),
      body: pages[_tabIndex],
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openCreateGroupDialog,
              icon: const Icon(Icons.group_add),
              label: const Text('グループ追加'),
            )
          : _tabIndex == 1
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const PhoneDialerScreen(initialTab: 0),
                    ),
                  ),
                  icon: const Icon(Icons.dialpad),
                  label: const Text('固定・携帯へ発信'),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (int i) => setState(() => _tabIndex = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.chat), label: 'トーク'),
          NavigationDestination(icon: Icon(Icons.videocam), label: '通話'),
          NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
 
  Widget _buildTalkTab() {
    final isWifi = NetworkGuard.isWifiOrEthernet(_connectivity);
    final isOff = NetworkGuard.isOffline(_connectivity);
    final visibleCategories = <String>['すべて', '個人'];
    for (final cat in const <String>['家族', '親戚', '仕事']) {
      if (widget.store.groups.any((g) => g.category == cat)) {
        visibleCategories.add(cat);
      }
    }
    for (final g in widget.store.groups) {
      if (!visibleCategories.contains(g.category)) {
        visibleCategories.add(g.category);
      }
    }
    final activeCategory = visibleCategories.contains(_selectedCategory)
        ? _selectedCategory
        : 'すべて';
    final filtered = activeCategory == 'すべて'
        ? widget.store.groups
        : widget.store.groups
            .where((g) => g.category == activeCategory)
            .toList();
 
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: <Widget>[
        if (widget.store.pendingUpdate != null)
          Card(
            color: const Color(0xFFE8F5E9),
            child: ListTile(
              leading: const Icon(Icons.system_update, color: Color(0xFF1B8A5A)),
              title: Text(
                '最新版 ${widget.store.pendingUpdate!.versionName} が公開されています',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(widget.store.pendingUpdate!.notes),
              trailing: FilledButton(
                onPressed: () async {
                  final ok = await NetworkGuard.confirmIfNotWifi(
                    context,
                    actionName: '最新APKのダウンロード',
                    warnOnNonWifi: widget.store.warnOnNonWifi,
                  );
                  if (ok && mounted) {
                    await ExternalAppLauncher.openUrl(
                      context,
                      widget.store.pendingUpdate!.apkUrl,
                    );
                  }
                },
                child: const Text('更新'),
              ),
            ),
          ),
 
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      isOff
                          ? Icons.wifi_off
                          : isWifi
                              ? Icons.wifi
                              : Icons.signal_cellular_alt,
                      color: isOff
                          ? Colors.red
                          : isWifi
                              ? Colors.green
                              : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${NetworkGuard.describe(_connectivity)} ／ 消去: ${formatExpireLabel(widget.store.defaultExpireHours)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2ECC87),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => ExternalAppLauncher.openTimeTree(context),
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: const Text('TimeTree'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF06C755),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => ExternalAppLauncher.openLine(context),
                        icon: const Icon(Icons.chat_bubble, size: 18),
                        label: const Text('LINE'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => AddMemberScreen(
                          store: widget.store,
                          initialTab: 2,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.person_add),
                    label: const Text('友だち追加・一覧（QR / ID / 削除）'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
 
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: visibleCategories
                .map(
                  (String cat) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: activeCategory == cat,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
 
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: const <Widget>[
                  Icon(Icons.forum_outlined, size: 40, color: Color(0xFF1B8A5A)),
                  SizedBox(height: 8),
                  Text(
                    'まだグループ・トークはありません',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '上の「友だち追加・一覧」から個人を登録するか、右下の「グループ追加」から作成できます。\n※ 作成したグループは長押しで名前変更・削除ができます。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),

        for (final group in filtered)
          Card(
            child: ListTile(
              onLongPress: () => _openRenameGroupDialog(group),
              leading: CircleAvatar(child: Text(initialLetter(group.category))),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(group.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (group.muted)
                    const Icon(Icons.notifications_off, size: 16, color: Colors.grey),
                ],
              ),
              subtitle: Text(
                group.draft.isNotEmpty
                    ? '[下書き] ${group.draft}'
                    : group.messages.isNotEmpty
                        ? (group.messages.last.deletedForAll
                            ? 'メッセージが取り消されました'
                            : '${group.messages.last.sender}: ${group.messages.last.text}')
                        : '${group.members.length}人 ・ 着信音: ${group.ringtone}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: '音声通話',
                    icon: const Icon(Icons.call),
                    onPressed: () => _startGroupCall(group, video: false),
                  ),
                  IconButton(
                    tooltip: 'ビデオ通話',
                    icon: const Icon(Icons.videocam),
                    onPressed: () => _startGroupCall(group, video: true),
                  ),
                ],
              ),
              onTap: () {
                widget.store.markAllRead(group.id);
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChatScreen(store: widget.store, groupId: group.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
 
  Widget _buildCallTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: <Widget>[
                Card(
          color: const Color(0xFFE8F5E9),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.dialpad, color: Color(0xFF1B8A5A)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '固定電話・携帯電話へ発信',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'スマホの通話回線を使って、固定電話や携帯電話へ発信できます。外線用の電話帳と発信履歴も保存できます。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const PhoneDialerScreen(initialTab: 0),
                          ),
                        ),
                        icon: const Icon(Icons.dialpad),
                        label: const Text('ダイヤル'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const PhoneDialerScreen(initialTab: 1),
                          ),
                        ),
                        icon: const Icon(Icons.contacts),
                        label: const Text('外線電話帳'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
Card(
          child: ListTile(
            leading: const Icon(Icons.graphic_eq, color: Color(0xFF1B8A5A)),
            title: const Text('複数人通話・ノイズキャンセリング・バックグラウンド着信'),
            subtitle: Text(
              widget.store.liveKitUrl.isEmpty
                  ? '現在：ローカル試用モード（設定タブでLiveKit接続先を設定可能）'
                  : '接続先設定済み：${widget.store.liveKitUrl}',
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.store.groups.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: Color(0xFF1B8A5A)),
              title: Text('アプリ内グループ通話'),
              subtitle: Text('トーク画面でグループや1対1トークを作成すると、ここから音声・ビデオ通話ができます。'),
            ),
          ),
        for (final group in widget.store.groups)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${group.name}（${group.category}・${group.members.length}人）',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('メンバー: ${group.members.join('、')}'),
                  Text('着信音: ${group.ringtone}'),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _startGroupCall(group, video: false),
                          icon: const Icon(Icons.call),
                          label: const Text('音声通話'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _startGroupCall(group, video: true),
                          icon: const Icon(Icons.videocam),
                          label: const Text('ビデオ通話'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
