import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../services/firebase_service.dart';
import '../services/push_callkit_incoming.dart';
import 'active_call_screen.dart';
import 'calls_tab.dart';
import 'chats_tab.dart';
import 'friends_tab.dart';
import 'settings_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;
  StreamSubscription<IncomingCallPayload>? _callKitAcceptSub;
  StreamSubscription<IncomingCallPayload>? _firestoreIncomingSub;

  @override
  void initState() {
    super.initState();
    _callKitAcceptSub =
        PushCallKitService.instance.onCallAccepted.listen(_openIncomingCall);

    _firestoreIncomingSub =
        FirebaseService.instance.onFirestoreIncomingCall.listen((payload) {
      PushCallKitService.showNativeIncomingCall(payload);
    });
  }

  void _openIncomingCall(IncomingCallPayload payload) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveCallScreen(
        incomingPayload: payload,
        isVideo: payload.isVideo,
      ),
    ));
  }

  @override
  void dispose() {
    _callKitAcceptSub?.cancel();
    _firestoreIncomingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fb = FirebaseService.instance;
    const titles = ['ホーム', 'トーク', '通話', '設定'];
    const pages = [
      FriendsTab(),
      ChatsTab(),
      CallsTab(),
      SettingsTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF9F2),
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: Row(
          children: [
            const Text('📞 ', style: TextStyle(fontSize: 20)),
            Text(
              titles[_tabIndex],
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: fb.firebaseReady
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                fb.firebaseReady ? 'Firebase接続' : 'デモ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: fb.firebaseReady
                      ? const Color(0xFF15803D)
                      : const Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => fb.toggleLargeFont(),
            child: Text(
              fb.largeFont ? '文字:大' : '文字:標準',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFFFEDD5),
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Color(0xFFEA580C)),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: Color(0xFFEA580C)),
            label: 'トーク',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call, color: Color(0xFFEA580C)),
            label: '通話',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFFEA580C)),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
