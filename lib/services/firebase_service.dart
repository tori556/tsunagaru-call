import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/app_models.dart';
import '../models/ringtone_prefs.dart';
import '../models/stamp_catalog.dart';

/// Firebase Auth / Firestore / Storage + Phase 3 グループ通話状態管理サービス
class FirebaseService extends ChangeNotifier {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  bool firebaseReady = false;
  bool largeFont = false;
  AppUser? currentUser;

  // Phase 3: LiveKit SFU グループ通話用設定（未設定時はデモモードで即体験可能）
  String liveKitUrl = '';
  String liveKitTokenEndpoint = '';

  // Phase 4: TURN 自動中継 & カテゴリ別着信音設定
  String turnEndpointUrl = '';
  String manualTurnUrl = '';
  String manualTurnUser = '';
  String manualTurnPass = '';
  RingtoneConfig ringtoneConfig = RingtoneConfig.defaults();

  final List<ContactItem> _contacts = [];
  final List<GroupChatRoom> _groups = [];
  final Map<String, List<ChatMessage>> _demoChats = {};
  final Map<String, List<ChatMessage>> _demoGroupMessages = {};
  final List<CallHistoryItem> _callHistory = [];

  List<ContactItem> get contacts => List.unmodifiable(_contacts);
  List<GroupChatRoom> get groups => List.unmodifiable(_groups);
  List<CallHistoryItem> get callHistory => List.unmodifiable(_callHistory);

  bool get isLiveKitConfigured =>
      liveKitUrl.trim().isNotEmpty && liveKitTokenEndpoint.trim().isNotEmpty;

  bool get isTurnConfigured =>
      turnEndpointUrl.trim().isNotEmpty || manualTurnUrl.trim().isNotEmpty;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incomingCallSub;

  final StreamController<IncomingCallPayload> _firestoreIncomingCtrl =
      StreamController<IncomingCallPayload>.broadcast();
  Stream<IncomingCallPayload> get onFirestoreIncomingCall =>
      _firestoreIncomingCtrl.stream;

  Future<void> initialize({required bool isFirebaseInitialized}) async {
    firebaseReady = isFirebaseInitialized;
    final prefs = await SharedPreferences.getInstance();
    largeFont = prefs.getBool('large_font') ?? false;
    liveKitUrl = prefs.getString('livekit_url') ?? '';
    liveKitTokenEndpoint = prefs.getString('livekit_token_endpoint') ?? '';
    turnEndpointUrl = prefs.getString('turn_endpoint_url') ?? '';
    manualTurnUrl = prefs.getString('manual_turn_url') ?? '';
    manualTurnUser = prefs.getString('manual_turn_user') ?? '';
    manualTurnPass = prefs.getString('manual_turn_pass') ?? '';
    ringtoneConfig = RingtoneConfig.fromJsonString(
      prefs.getString('ringtone_config_json'),
    );

    final savedName = prefs.getString('display_name') ?? '自分';
    final savedEmoji = prefs.getString('emoji') ?? '👨';
    final savedMyId = prefs.getString('my_id') ?? _generateMyId();
    final savedStatus = prefs.getString('status_msg') ?? '電話OK';
    await prefs.setString('my_id', savedMyId);

    if (firebaseReady) {
      try {
        final auth = FirebaseAuth.instance;
        User? fbUser = auth.currentUser;
        fbUser ??= (await auth.signInAnonymously()).user;
        final uid = fbUser?.uid ?? 'local_$savedMyId';

        currentUser = AppUser(
          uid: uid,
          myId: savedMyId,
          displayName: savedName,
          emoji: savedEmoji,
          statusMessage: savedStatus,
          email: fbUser?.email,
          isOnline: true,
        );

        await _syncProfileToFirestore();
        _listenFirestoreContacts(uid);
        _listenFirestoreGroups(uid);
        _listenIncomingCallsInForeground(uid);
      } catch (e) {
        debugPrint('Firebase fallback to demo mode: $e');
        firebaseReady = false;
        _initDemoState(savedMyId, savedName, savedEmoji, savedStatus);
      }
    } else {
      _initDemoState(savedMyId, savedName, savedEmoji, savedStatus);
    }
    notifyListeners();
  }

  Future<void> saveLiveKitConfig({
    required String url,
    required String tokenEndpoint,
  }) async {
    liveKitUrl = url.trim();
    liveKitTokenEndpoint = tokenEndpoint.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('livekit_url', liveKitUrl);
    await prefs.setString('livekit_token_endpoint', liveKitTokenEndpoint);
    notifyListeners();
  }

  /// Phase 4: TURN 自動取得エンドポイント／手動TURN設定を保存
  Future<void> saveTurnConfig({
    required String endpointUrl,
    required String turnUrl,
    required String username,
    required String credential,
  }) async {
    turnEndpointUrl = endpointUrl.trim();
    manualTurnUrl = turnUrl.trim();
    manualTurnUser = username.trim();
    manualTurnPass = credential.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('turn_endpoint_url', turnEndpointUrl);
    await prefs.setString('manual_turn_url', manualTurnUrl);
    await prefs.setString('manual_turn_user', manualTurnUser);
    await prefs.setString('manual_turn_pass', manualTurnPass);
    notifyListeners();
  }

  /// Phase 4: STUN + TURN（自動取得または手動）を組み立てて WebRTC へ提供
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
    ];

    if (manualTurnUrl.isNotEmpty) {
      servers.add({
        'urls': manualTurnUrl,
        if (manualTurnUser.isNotEmpty) 'username': manualTurnUser,
        if (manualTurnPass.isNotEmpty) 'credential': manualTurnPass,
      });
    }

    if (turnEndpointUrl.isNotEmpty) {
      try {
        final res = await http
            .post(
              Uri.parse(turnEndpointUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'uid': currentUser?.uid ?? 'guest'}),
            )
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body is Map && body['iceServers'] is List) {
            for (final item in body['iceServers'] as List) {
              if (item is Map) {
                servers.add(Map<String, dynamic>.from(item));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('TURN auto-fetch fallback to STUN: $e');
      }
    }

    return servers;
  }

  /// Phase 4: カテゴリ別の着信音・バイブレーション設定を更新
  Future<void> updateCategoryRingtone(
    ContactCategory category,
    CategoryRingtoneSetting setting,
  ) async {
    ringtoneConfig = ringtoneConfig.withUpdated(category, setting);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ringtone_config_json', ringtoneConfig.toJsonString());
    notifyListeners();
  }

  /// Phase 4: iOS PushKit VoIP トークンを Firestore に保存
  Future<void> updateVoipToken(String token) async {
    if (currentUser == null || token.trim().isEmpty) return;
    currentUser = currentUser!.copyWith(voipToken: token.trim());
    await _syncProfileToFirestore();
    notifyListeners();
  }


  void _initDemoState(
    String myId,
    String name,
    String emoji,
    String status,
  ) {
    currentUser = AppUser(
      uid: 'demo_self',
      myId: myId,
      displayName: name,
      emoji: emoji,
      statusMessage: status,
      isOnline: true,
    );

    if (_contacts.isEmpty) {
      final now = DateTime.now();
      _contacts.addAll([
        ContactItem(
          id: 'demo_1',
          targetUid: 'demo_grandma',
          targetMyId: 'fm-obaachan',
          name: 'おばあちゃん',
          emoji: '👵',
          category: ContactCategory.family,
          memo: '実家',
          pinned: true,
          isOnline: true,
          statusText: '家にいるよ',
          lastMessage: '今日はいい天気だね☀️ 夕方みんなでグループ通話しよう！',
          lastMessageAt: now.subtract(const Duration(minutes: 8)),
          unreadCount: 1,
        ),
        ContactItem(
          id: 'demo_2',
          targetUid: 'demo_kenta',
          targetMyId: 'fr-kenta88',
          name: 'けんた',
          emoji: '🧑',
          category: ContactCategory.friends,
          memo: '高校の同級生',
          isOnline: true,
          statusText: '電話OK',
          lastMessage: '週末の集合時間どうする？',
          lastMessageAt: now.subtract(const Duration(hours: 2)),
        ),
        ContactItem(
          id: 'demo_3',
          targetUid: 'demo_sato',
          targetMyId: 'wk-sato01',
          name: '佐藤課長',
          emoji: '👨‍💼',
          category: ContactCategory.work,
          memo: '企画部',
          isOnline: false,
          statusText: '会議中',
          lastMessage: '資料の確認ありがとうございます。',
          lastMessageAt: now.subtract(const Duration(hours: 5)),
        ),
        ContactItem(
          id: 'demo_4',
          targetUid: 'demo_uncle',
          targetMyId: 'rl-ojisan',
          name: '岡山のおじさん',
          emoji: '👴',
          category: ContactCategory.relatives,
          memo: '親戚',
          isOnline: true,
          statusText: '電話OK',
          lastMessage: '今度みんなで集まろうね！',
          lastMessageAt: now.subtract(const Duration(days: 1)),
        ),
        ContactItem(
          id: 'demo_5',
          targetUid: 'demo_local',
          targetMyId: 'ot-chiiki',
          name: '地域の連絡係',
          emoji: '✨',
          category: ContactCategory.other,
          memo: '町内会',
          isOnline: false,
          statusText: '待機中',
        ),
      ]);

      _demoChats[chatRoomId('demo_self', 'demo_grandma')] = [
        ChatMessage(
          id: 'm0',
          senderUid: 'demo_grandma',
          senderName: 'おばあちゃん',
          senderEmoji: '👵',
          text: 'おはよう！',
          isStamp: true,
          stampId: 'cel_morning',
          createdAt: now.subtract(const Duration(minutes: 30)),
          isRead: true,
        ),
        ChatMessage(
          id: 'm1',
          senderUid: 'demo_grandma',
          senderName: 'おばあちゃん',
          senderEmoji: '👵',
          text: '今日はいい天気だね☀️ 夕方みんなでグループ通話しよう！',
          createdAt: now.subtract(const Duration(minutes: 8)),
          isRead: false,
        ),
      ];
      _demoChats[chatRoomId('demo_self', 'demo_kenta')] = [
        ChatMessage(
          id: 'm2',
          senderUid: 'demo_kenta',
          senderName: 'けんた',
          senderEmoji: '🧑',
          text: '週末の集合時間どうする？',
          createdAt: now.subtract(const Duration(hours: 2)),
          isRead: true,
        ),
      ];

      _groups.add(GroupChatRoom(
        id: 'demo_group_family',
        name: '家族連絡グループ',
        emoji: '🏠',
        category: ContactCategory.family,
        memberUids: ['demo_self', 'demo_grandma', 'demo_uncle'],
        memberNames: {
          'demo_self': name,
          'demo_grandma': 'おばあちゃん',
          'demo_uncle': '岡山のおじさん',
        },
        lastMessage: '今週末のごはん何時にする？🍚',
        lastMessageAt: now.subtract(const Duration(minutes: 20)),
        unreadCount: 1,
      ));

      _demoGroupMessages['demo_group_family'] = [
        ChatMessage(
          id: 'gm0',
          senderUid: 'demo_uncle',
          senderName: '岡山のおじさん',
          senderEmoji: '👴',
          text: '承知いたしました',
          isStamp: true,
          stampId: 'fam_ok',
          createdAt: now.subtract(const Duration(minutes: 40)),
          readBy: ['demo_grandma'],
        ),
        ChatMessage(
          id: 'gm1',
          senderUid: 'demo_grandma',
          senderName: 'おばあちゃん',
          senderEmoji: '👵',
          text: '今週末のごはん何時にする？🍚',
          createdAt: now.subtract(const Duration(minutes: 20)),
          readBy: ['demo_uncle'],
        ),
      ];
    }
  }

  String _generateMyId() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random();
    String part() => List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'ln-${part()}-${part()}';
  }

  String chatRoomId(String uidA, String uidB) {
    final list = [uidA, uidB]..sort();
    return '${list[0]}__${list[1]}';
  }

  String buildMyQrData() {
    final me = currentUser;
    if (me == null) return '';
    return Uri(
      scheme: 'tsunagarucall',
      host: 'add',
      queryParameters: {
        'myId': me.myId,
        'name': me.displayName,
        'emoji': me.emoji,
      },
    ).toString();
  }

  Map<String, String>? parseQrData(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme == 'tsunagarucall' && uri.queryParameters['myId'] != null) {
        return {
          'myId': uri.queryParameters['myId']!,
          'name': uri.queryParameters['name'] ?? '',
          'emoji': uri.queryParameters['emoji'] ?? '😊',
        };
      }
    } catch (_) {}
    if (RegExp(r'^[a-zA-Z0-9_-]{4,32}$').hasMatch(trimmed)) {
      return {'myId': trimmed.toLowerCase(), 'name': '', 'emoji': '😊'};
    }
    return null;
  }

  Future<void> toggleLargeFont() async {
    largeFont = !largeFont;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('large_font', largeFont);
    notifyListeners();
  }

  Future<void> updateProfile({
    required String displayName,
    required String emoji,
    String? statusMessage,
  }) async {
    if (currentUser == null) return;
    currentUser = currentUser!.copyWith(
      displayName: displayName,
      emoji: emoji,
      statusMessage: statusMessage ?? currentUser!.statusMessage,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_name', currentUser!.displayName);
    await prefs.setString('emoji', currentUser!.emoji);
    await prefs.setString('status_msg', currentUser!.statusMessage);
    await _syncProfileToFirestore();
    notifyListeners();
  }

  Future<String?> linkEmailAccount({
    required String email,
    required String password,
  }) async {
    if (!firebaseReady) {
      return 'デモモードではアカウント連携できません。Firebase設定後にご利用ください。';
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'ログイン状態を確認できません';
      final cred = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );
      await user.linkWithCredential(cred);
      currentUser = currentUser?.copyWith(email: email.trim());
      await _syncProfileToFirestore();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'アカウント連携に失敗しました';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!firebaseReady) {
      return 'デモモードではログインできません。Firebase設定後にご利用ください。';
    }
    try {
      final res = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = res.user?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && doc.data() != null) {
          currentUser = AppUser.fromMap({...doc.data()!, 'uid': uid});
        }
        _listenFirestoreContacts(uid);
        _listenFirestoreGroups(uid);
        _listenIncomingCallsInForeground(uid);
        notifyListeners();
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'ログインに失敗しました';
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> updateFcmToken(String token) async {
    if (currentUser == null) return;
    currentUser = currentUser!.copyWith(fcmToken: token);
    await _syncProfileToFirestore();
    notifyListeners();
  }

  Future<void> _syncProfileToFirestore() async {
    if (!firebaseReady || currentUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .set({
        ...currentUser!.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Profile sync error: $e');
    }
  }

  void _listenFirestoreContacts(String uid) {
    _contactsSub?.cancel();
    _contactsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .snapshots()
        .listen((snap) {
      _contacts
        ..clear()
        ..addAll(snap.docs.map((d) => ContactItem.fromMap({
              ...d.data(),
              'id': d.id,
            })));
      notifyListeners();
    });
  }

  void _listenFirestoreGroups(String uid) {
    _groupsSub?.cancel();
    _groupsSub = FirebaseFirestore.instance
        .collection('groups')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      _groups
        ..clear()
        ..addAll(snap.docs.map((d) => GroupChatRoom.fromMap(d.id, d.data())));
      notifyListeners();
    });
  }

  void _listenIncomingCallsInForeground(String uid) {
    _incomingCallSub?.cancel();
    _incomingCallSub = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeUid', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d == null) continue;
          _firestoreIncomingCtrl.add(IncomingCallPayload(
            callId: change.doc.id,
            callerUid: (d['callerUid'] ?? '').toString(),
            callerName: (d['callerName'] ?? '着信相手').toString(),
            callerEmoji: (d['callerEmoji'] ?? '📞').toString(),
            category: ContactCategory.fromId(d['category']?.toString()),
            isVideo: d['isVideo'] == true,
          ));
        }
      }
    });
  }

  Future<String?> addContactByMyId({
    required String targetMyId,
    required String nickname,
    required ContactCategory category,
    required String emoji,
    required String memo,
  }) async {
    final cleanId = targetMyId.trim().toLowerCase();
    if (cleanId.isEmpty) return '相手のマイIDを入力してください';
    if (cleanId == currentUser?.myId) return '自分自身は追加できません';

    String targetUid = 'uid_$cleanId';
    String resolvedName = nickname.trim();

    if (firebaseReady) {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('myId', isEqualTo: cleanId)
          .limit(1)
          .get();
      if (q.docs.isEmpty) {
        return 'マイID「$cleanId」のユーザーが見つかりませんでした';
      }
      final doc = q.docs.first;
      targetUid = doc.id;
      if (resolvedName.isEmpty) {
        resolvedName = (doc.data()['displayName'] ?? cleanId).toString();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('contacts')
          .doc(targetUid)
          .set({
        'id': targetUid,
        'targetUid': targetUid,
        'targetMyId': cleanId,
        'name': resolvedName,
        'emoji': emoji,
        'category': category.id,
        'memo': memo.trim(),
        'pinned': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return null;
    }

    final item = ContactItem(
      id: 'ct_${DateTime.now().millisecondsSinceEpoch}',
      targetUid: targetUid,
      targetMyId: cleanId,
      name: resolvedName.isEmpty ? cleanId : resolvedName,
      emoji: emoji,
      category: category,
      memo: memo.trim(),
      isOnline: true,
      statusText: '電話OK',
    );
    _contacts.add(item);
    notifyListeners();
    return null;
  }

  Future<void> togglePin(ContactItem item) async {
    final nextPinned = !item.pinned;
    if (firebaseReady && currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('contacts')
          .doc(item.id)
          .update({'pinned': nextPinned});
    } else {
      final idx = _contacts.indexWhere((c) => c.id == item.id);
      if (idx >= 0) {
        _contacts[idx] = _contacts[idx].copyWith(pinned: nextPinned);
        notifyListeners();
      }
    }
  }

  Future<void> updateContactCategory(
    ContactItem item,
    ContactCategory nextCategory,
  ) async {
    if (firebaseReady && currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('contacts')
          .doc(item.id)
          .update({'category': nextCategory.id});
    } else {
      final idx = _contacts.indexWhere((c) => c.id == item.id);
      if (idx >= 0) {
        _contacts[idx] = _contacts[idx].copyWith(category: nextCategory);
        notifyListeners();
      }
    }
  }

  Future<void> deleteContact(ContactItem item) async {
    if (firebaseReady && currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('contacts')
          .doc(item.id)
          .delete();
    } else {
      _contacts.removeWhere((c) => c.id == item.id);
      notifyListeners();
    }
  }

  Future<String?> _uploadChatImage(String folderId, File file) async {
    if (!firebaseReady) return null;
    final fileName = '${const Uuid().v4()}.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child(folderId)
        .child(fileName);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  // ---------- 1対1 トーク ----------
  Stream<List<ChatMessage>> watchMessages(String targetUid) {
    final myUid = currentUser?.uid ?? 'demo_self';
    final roomId = chatRoomId(myUid, targetUid);

    if (firebaseReady) {
      return FirebaseFirestore.instance
          .collection('chats')
          .doc(roomId)
          .collection('messages')
          .orderBy('createdAtMs', descending: false)
          .limitToLast(200)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => ChatMessage.fromMap(d.id, d.data()))
              .toList());
    }

    return Stream<List<ChatMessage>>.periodic(
      const Duration(milliseconds: 350),
      (_) => List<ChatMessage>.from(_demoChats[roomId] ?? const []),
    ).asBroadcastStream();
  }

  Future<void> sendMessage({
    required ContactItem target,
    required String text,
    bool isStamp = false,
    String? stampId,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || currentUser == null) return;
    final roomId = chatRoomId(currentUser!.uid, target.targetUid);
    final now = DateTime.now();
    final preview = isStamp ? '【スタンプ】$clean' : clean;

    if (firebaseReady) {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(roomId);
      await chatRef.set({
        'participants': [currentUser!.uid, target.targetUid],
        'lastMessage': preview,
        'lastMessageAtMs': now.millisecondsSinceEpoch,
        'lastSenderUid': currentUser!.uid,
        'lastSenderName': currentUser!.displayName,
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderUid': currentUser!.uid,
        'receiverUid': target.targetUid,
        'senderName': currentUser!.displayName,
        'senderEmoji': currentUser!.emoji,
        'text': clean,
        'isStamp': isStamp,
        'stampId': stampId ?? '',
        'createdAtMs': now.millisecondsSinceEpoch,
        'isRead': false,
      });
    } else {
      final list = _demoChats.putIfAbsent(roomId, () => []);
      list.add(ChatMessage(
        id: 'msg_${now.millisecondsSinceEpoch}',
        senderUid: currentUser!.uid,
        senderName: currentUser!.displayName,
        senderEmoji: currentUser!.emoji,
        text: clean,
        isStamp: isStamp,
        stampId: stampId,
        createdAt: now,
        isRead: true,
      ));
      final idx = _contacts.indexWhere((c) => c.id == target.id);
      if (idx >= 0) {
        _contacts[idx] = _contacts[idx].copyWith(
          lastMessage: preview,
          lastMessageAt: now,
          unreadCount: 0,
        );
      }
      notifyListeners();
    }
  }

  Future<void> sendStampToContact(ContactItem target, StampItem stamp) {
    return sendMessage(
      target: target,
      text: '${stamp.emoji} ${stamp.label}',
      isStamp: true,
      stampId: stamp.id,
    );
  }

  Future<void> sendImageMessage({
    required ContactItem target,
    required File imageFile,
  }) async {
    if (currentUser == null) return;
    final roomId = chatRoomId(currentUser!.uid, target.targetUid);
    final now = DateTime.now();

    if (firebaseReady) {
      final url = await _uploadChatImage(roomId, imageFile);
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(roomId);
      await chatRef.set({
        'participants': [currentUser!.uid, target.targetUid],
        'lastMessage': '📷 写真を送信しました',
        'lastMessageAtMs': now.millisecondsSinceEpoch,
        'lastSenderUid': currentUser!.uid,
        'lastSenderName': currentUser!.displayName,
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderUid': currentUser!.uid,
        'receiverUid': target.targetUid,
        'senderName': currentUser!.displayName,
        'senderEmoji': currentUser!.emoji,
        'text': '',
        'imageUrl': url,
        'isStamp': false,
        'createdAtMs': now.millisecondsSinceEpoch,
        'isRead': false,
      });
    } else {
      final list = _demoChats.putIfAbsent(roomId, () => []);
      list.add(ChatMessage(
        id: 'img_${now.millisecondsSinceEpoch}',
        senderUid: currentUser!.uid,
        senderName: currentUser!.displayName,
        senderEmoji: currentUser!.emoji,
        text: '',
        localImagePath: imageFile.path,
        createdAt: now,
        isRead: true,
      ));
      final idx = _contacts.indexWhere((c) => c.id == target.id);
      if (idx >= 0) {
        _contacts[idx] = _contacts[idx].copyWith(
          lastMessage: '📷 写真を送信しました',
          lastMessageAt: now,
          unreadCount: 0,
        );
      }
      notifyListeners();
    }
  }

  Future<void> markChatRead(ContactItem target) async {
    if (currentUser == null) return;
    if (!firebaseReady) {
      final idx = _contacts.indexWhere((c) => c.id == target.id);
      if (idx >= 0 && _contacts[idx].unreadCount > 0) {
        _contacts[idx] = _contacts[idx].copyWith(unreadCount: 0);
        notifyListeners();
      }
      return;
    }
    final roomId = chatRoomId(currentUser!.uid, target.targetUid);
    try {
      final unread = await FirebaseFirestore.instance
          .collection('chats')
          .doc(roomId)
          .collection('messages')
          .where('senderUid', isEqualTo: target.targetUid)
          .where('isRead', isEqualTo: false)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in unread.docs) {
        batch.update(d.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (_) {}
  }

  // ---------- グループトーク & Phase 3 グループ通話状態 ----------
  GroupChatRoom? findGroupById(String groupId) {
    for (final g in _groups) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  Future<GroupChatRoom?> createGroup({
    required String name,
    required String emoji,
    required ContactCategory category,
    required List<ContactItem> members,
  }) async {
    if (currentUser == null || name.trim().isEmpty) return null;
    final uids = <String>[
      currentUser!.uid,
      ...members.map((m) => m.targetUid),
    ];
    final names = <String, String>{
      currentUser!.uid: currentUser!.displayName,
      for (final m in members) m.targetUid: m.name,
    };
    final now = DateTime.now();

    if (firebaseReady) {
      final ref = await FirebaseFirestore.instance.collection('groups').add({
        'name': name.trim(),
        'emoji': emoji,
        'category': category.id,
        'memberUids': uids,
        'memberNames': names,
        'lastMessage': '${currentUser!.displayName}がグループを作成しました',
        'lastMessageAtMs': now.millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return GroupChatRoom(
        id: ref.id,
        name: name.trim(),
        emoji: emoji,
        category: category,
        memberUids: uids,
        memberNames: names,
        lastMessage: '${currentUser!.displayName}がグループを作成しました',
        lastMessageAt: now,
      );
    }

    final room = GroupChatRoom(
      id: 'grp_${now.millisecondsSinceEpoch}',
      name: name.trim(),
      emoji: emoji,
      category: category,
      memberUids: uids,
      memberNames: names,
      lastMessage: '${currentUser!.displayName}がグループを作成しました',
      lastMessageAt: now,
    );
    _groups.insert(0, room);
    _demoGroupMessages[room.id] = [];
    notifyListeners();
    return room;
  }

  Stream<List<ChatMessage>> watchGroupMessages(String groupId) {
    if (firebaseReady) {
      return FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('createdAtMs', descending: false)
          .limitToLast(200)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => ChatMessage.fromMap(d.id, d.data()))
              .toList());
    }
    return Stream<List<ChatMessage>>.periodic(
      const Duration(milliseconds: 350),
      (_) => List<ChatMessage>.from(_demoGroupMessages[groupId] ?? const []),
    ).asBroadcastStream();
  }

  Future<void> sendGroupMessage({
    required GroupChatRoom group,
    String text = '',
    bool isStamp = false,
    String? stampId,
    File? imageFile,
  }) async {
    if (currentUser == null) return;
    final clean = text.trim();
    if (clean.isEmpty && imageFile == null) return;
    final now = DateTime.now();

    final summary = imageFile != null
        ? '📷 写真を送信しました'
        : (isStamp ? '【スタンプ】$clean' : clean);

    if (firebaseReady) {
      String? url;
      if (imageFile != null) {
        url = await _uploadChatImage('group_${group.id}', imageFile);
      }
      final gRef = FirebaseFirestore.instance.collection('groups').doc(group.id);
      await gRef.set({
        'lastMessage': '${currentUser!.displayName}: $summary',
        'lastMessageAtMs': now.millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      await gRef.collection('messages').add({
        'senderUid': currentUser!.uid,
        'senderName': currentUser!.displayName,
        'senderEmoji': currentUser!.emoji,
        'text': clean,
        'imageUrl': url,
        'isStamp': isStamp,
        'stampId': stampId ?? '',
        'createdAtMs': now.millisecondsSinceEpoch,
        'readBy': <String>[],
      });
    } else {
      final list = _demoGroupMessages.putIfAbsent(group.id, () => []);
      list.add(ChatMessage(
        id: 'gmsg_${now.millisecondsSinceEpoch}',
        senderUid: currentUser!.uid,
        senderName: currentUser!.displayName,
        senderEmoji: currentUser!.emoji,
        text: clean,
        localImagePath: imageFile?.path,
        isStamp: isStamp,
        stampId: stampId,
        createdAt: now,
        readBy: group.memberUids.where((u) => u != currentUser!.uid).toList(),
      ));
      final idx = _groups.indexWhere((g) => g.id == group.id);
      if (idx >= 0) {
        _groups[idx] = _groups[idx].copyWith(
          lastMessage: '${currentUser!.displayName}: $summary',
          lastMessageAt: now,
          unreadCount: 0,
        );
      }
      notifyListeners();
    }
  }

  Future<void> sendStampToGroup(GroupChatRoom group, StampItem stamp) {
    return sendGroupMessage(
      group: group,
      text: '${stamp.emoji} ${stamp.label}',
      isStamp: true,
      stampId: stamp.id,
    );
  }

  Future<void> markGroupRead(GroupChatRoom group) async {
    if (currentUser == null) return;
    if (!firebaseReady) {
      final idx = _groups.indexWhere((g) => g.id == group.id);
      if (idx >= 0 && _groups[idx].unreadCount > 0) {
        _groups[idx] = _groups[idx].copyWith(unreadCount: 0);
        notifyListeners();
      }
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('groups')
          .doc(group.id)
          .collection('messages')
          .orderBy('createdAtMs', descending: true)
          .limit(30)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        final data = d.data();
        if (data['senderUid'] != currentUser!.uid) {
          batch.update(d.reference, {
            'readBy': FieldValue.arrayUnion([currentUser!.uid]),
          });
        }
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Phase 3: グループ通話の開始・参加を Firestore に記録（開始時に Cloud Functions が全員へ通知）
  Future<GroupCallSession> startOrJoinGroupCall({
    required GroupChatRoom group,
    required bool isVideo,
  }) async {
    final me = currentUser!;
    final roomName = group.activeCall?.roomName.isNotEmpty == true
        ? group.activeCall!.roomName
        : 'grp_${group.id}';

    final existingUids = List<String>.from(
      group.activeCall?.activeParticipantUids ?? const [],
    );
    if (!existingUids.contains(me.uid)) {
      existingUids.add(me.uid);
    }

    final session = GroupCallSession(
      roomName: roomName,
      isVideo: group.activeCall?.isVideo ?? isVideo,
      startedByName: group.activeCall?.startedByName ?? me.displayName,
      activeParticipantUids: existingUids,
      startedAt: group.activeCall?.startedAt ?? DateTime.now(),
    );

    if (firebaseReady) {
      await FirebaseFirestore.instance.collection('groups').doc(group.id).set({
        'activeCall': session.toMap(),
      }, SetOptions(merge: true));
    } else {
      final idx = _groups.indexWhere((g) => g.id == group.id);
      if (idx >= 0) {
        _groups[idx] = _groups[idx].copyWith(activeCall: session);
        notifyListeners();
      }
    }
    return session;
  }

  /// Phase 3: グループ通話から退出（全員退出したら activeCall をクリア）
  Future<void> leaveGroupCall(GroupChatRoom group) async {
    final me = currentUser;
    if (me == null) return;

    if (firebaseReady) {
      final ref = FirebaseFirestore.instance.collection('groups').doc(group.id);
      final snap = await ref.get();
      final raw = snap.data()?['activeCall'];
      if (raw is Map) {
        final cur = GroupCallSession.fromMap(Map<String, dynamic>.from(raw));
        final nextUids =
            cur.activeParticipantUids.where((u) => u != me.uid).toList();
        if (nextUids.isEmpty) {
          await ref.update({'activeCall': FieldValue.delete()});
        } else {
          await ref.update({'activeCall.activeParticipantUids': nextUids});
        }
      }
    } else {
      final idx = _groups.indexWhere((g) => g.id == group.id);
      if (idx >= 0) {
        _groups[idx] = _groups[idx].copyWith(clearActiveCall: true);
        notifyListeners();
      }
    }
  }

  void addCallHistory(CallHistoryItem item) {
    _callHistory.insert(0, item);
    if (_callHistory.length > 50) _callHistory.removeLast();
    notifyListeners();
  }
}
