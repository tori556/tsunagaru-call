import 'dart:async';
import 'dart:convert';
import 'dart:io';
 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
 
import '../models.dart';
import 'core_services.dart';
 
typedef QuerySnap = QuerySnapshot<JsonMap>;
typedef QuerySub = StreamSubscription<QuerySnap>;
 
final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
 
String ringtoneChannelId(String ringtone) {
  final idx = ringtoneOptions.indexOf(ringtone);
  return 'tsunagaru_call_ch_${idx >= 0 ? idx : 0}';
}
 
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
 
  final data = message.data;
  if (data['type'] == 'incoming_call') {
    final payload = IncomingCallPayload.fromMap(data);
    if (payload.isStale) return;
    await CloudSyncService.showIncomingCallNotification(payload);
  } else if (data['type'] == 'cancel_call') {
    final callId = (data['callId'] ?? '').toString();
    if (callId.isNotEmpty) {
      await localNotificationsPlugin.cancel(callId.hashCode & 0x7fffffff);
    }
  }
}
 
class CloudSyncService {
  bool isReady = false;
  String? uid;
  String? fcmToken;
  String statusLabel = 'ローカルモード（google-services.json 未設定）';
 
  final Set<String> _handledCallIds = <String>{};
  final Map<String, QuerySub> _msgSubs = <String, QuerySub>{};
  QuerySub? _groupSub;
 
  void Function(IncomingCallPayload payload)? onIncomingCall;
  void Function(String callId)? onCallCancelled;
 
  Future<void> init({
    required String inviteId,
    required String displayName,
  }) async {
    await _initLocalNotificationChannels();
 
    try {
      await Firebase.initializeApp();
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      uid = auth.currentUser?.uid;
 
      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission(alert: true, badge: true, sound: true);
      fcmToken = await fcm.getToken();
 
      FirebaseMessaging.onMessage.listen(_handleRemoteMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessage);
 
      final initialMsg = await fcm.getInitialMessage();
      if (initialMsg != null) {
        _handleRemoteMessage(initialMsg);
      }
 
      isReady = true;
      statusLabel = 'Firebase 双方向クラウド同期有効';
 
      await syncUserProfile(inviteId: inviteId, displayName: displayName);
    } catch (e, s) {
      isReady = false;
      statusLabel = 'ローカル動作モード（Firebase未接続）';
      ErrorGuard.record('Firebase初期化スキップ（ローカル継続）: $e', s);
    }
  }
 
  Future<void> _initLocalNotificationChannels() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await localNotificationsPlugin.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: (NotificationResponse res) {
          if (res.payload != null && res.payload!.isNotEmpty) {
            try {
              final map = jsonDecode(res.payload!) as JsonMap;
              final payload = IncomingCallPayload.fromMap(map);
              if (!payload.isStale) {
                onIncomingCall?.call(payload);
              }
            } catch (_) {}
          }
        },
      );
 
      final androidPlugin =
          localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
 
        for (var i = 0; i < ringtoneOptions.length; i++) {
          await androidPlugin.createNotificationChannel(
            AndroidNotificationChannel(
              'tsunagaru_call_ch_$i',
              '着信通知（${ringtoneOptions[i]}）',
              description: 'アプリ終了時にも着信画面・着信音を表示するチャンネル',
              importance: Importance.max,
              playSound: true,
            ),
          );
        }
      }
    } catch (e, s) {
      ErrorGuard.record('通知チャンネル初期化エラー: $e', s);
    }
  }
 
  void _handleRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    if (type == 'incoming_call') {
      final payload = IncomingCallPayload.fromMap(data);
      if (payload.isStale) return;
      if (_handledCallIds.contains(payload.callId)) return;
      _handledCallIds.add(payload.callId);
      onIncomingCall?.call(payload);
    } else if (type == 'cancel_call') {
      final callId = (data['callId'] ?? '').toString();
      if (callId.isNotEmpty) {
        localNotificationsPlugin.cancel(callId.hashCode & 0x7fffffff);
        onCallCancelled?.call(callId);
      }
    }
  }
 
  static Future<void> showIncomingCallNotification(
    IncomingCallPayload payload,
  ) async {
    final chId = ringtoneChannelId(payload.ringtone);
    final notifId = payload.callId.hashCode & 0x7fffffff;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        chId,
        '着信通知（${payload.ringtone}）',
        channelDescription: 'tranceferの着信通知',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: true,
        playSound: true,
      ),
    );
    await localNotificationsPlugin.show(
      notifId,
      '${payload.callerName} から${payload.isVideo ? "ビデオ" : "音声"}着信',
      'グループ: ${payload.groupName}（${payload.ringtone}）',
      details,
      payload: jsonEncode(payload.toMap()),
    );
  }
 
  Future<void> syncUserProfile({
    required String inviteId,
    required String displayName,
    int defaultExpireHours = 0,
    bool showOnline = true,
    bool showLastSeen = true,
    bool shareTyping = true,
  }) async {
    if (!isReady || uid == null) return;
    try {
      final fs = FirebaseFirestore.instance;
      await fs.collection('users').doc(uid).set(<String, dynamic>{
        'inviteId': inviteId,
        'displayName': displayName,
        if (fcmToken != null)
          'fcmTokens': FieldValue.arrayUnion(<String>[fcmToken!]),
        'defaultExpireHours': defaultExpireHours,
        'privacy': <String, dynamic>{
          'showOnlineStatus': showOnline,
          'showLastSeen': showLastSeen,
          'shareTypingStatus': shareTyping,
        },
        'online': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
 
      await fs.collection('inviteIndex').doc(inviteId).set(<String, dynamic>{
        'inviteId': inviteId,
        'displayName': displayName,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, s) {
      ErrorGuard.record('プロフィール同期エラー: $e', s);
    }
  }
 
  void listenMyGroups(void Function(List<ChatGroup> remoteGroups) onUpdate) {
    if (!isReady || uid == null) return;
    _groupSub?.cancel();
    _groupSub = FirebaseFirestore.instance
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .listen(
      (QuerySnap snap) {
        final list = snap.docs.map((doc) {
          final data = JsonMap.from(doc.data())..['id'] = doc.id;
          return ChatGroup.fromJson(data);
        }).toList();
        onUpdate(list);
      },
      onError: (dynamic e, StackTrace s) {
        ErrorGuard.record('グループ購読エラー: $e', s);
      },
    );
  }
 
  void listenGroupMessages(
    String groupId,
    void Function(List<ChatMessage> remoteMessages) onUpdate,
  ) {
    if (!isReady || uid == null) return;
    if (_msgSubs.containsKey(groupId)) return;
    _msgSubs[groupId] = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limitToLast(200)
        .snapshots()
        .listen(
      (QuerySnap snap) {
        final msgs = snap.docs.map((doc) {
          final data = JsonMap.from(doc.data())..['id'] = doc.id;
          return ChatMessage.fromJson(data);
        }).toList();
        onUpdate(msgs);
      },
      onError: (dynamic e, StackTrace s) {
        ErrorGuard.record('メッセージ購読エラー ($groupId): $e', s);
      },
    );
  }
 
  Future<void> syncGroupToCloud(ChatGroup group) async {
    if (!isReady || uid == null) return;
    try {
      final memberIds = <String>{uid!, ...group.memberUids}.toList();
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(group.id)
          .set(<String, dynamic>{
        'name': group.name,
        'category': group.category,
        'members': group.members,
        'memberIds': memberIds,
        'pinnedMessageId': group.pinnedMessageId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
 
      await syncMemberSettingToCloud(
        group.id,
        muted: group.muted,
        ringtone: group.ringtone,
      );
    } catch (e, s) {
      ErrorGuard.record('グループ同期エラー: $e', s);
    }
  }
 
  Future<void> syncMemberSettingToCloud(
    String groupId, {
    required bool muted,
    required String ringtone,
  }) async {
    if (!isReady || uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('memberSettings')
          .doc(uid)
          .set(<String, dynamic>{
        'muted': muted,
        'ringtone': ringtone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, s) {
      ErrorGuard.record('トーク設定同期エラー: $e', s);
    }
  }
 
  Future<MemberProfile?> lookupInviteId(String inviteId) async {
    if (!isReady) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('inviteIndex')
          .doc(inviteId.trim().toUpperCase())
          .get();
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;
      return MemberProfile(
        inviteId: (d['inviteId'] as String?) ?? inviteId,
        name: (d['displayName'] as String?) ?? 'メンバー',
        uid: d['uid'] as String?,
      );
    } catch (e, s) {
      ErrorGuard.record('ID検索エラー: $e', s);
      return null;
    }
  }
 
  Future<MediaAttachment?> uploadFileStream({
    required String groupId,
    required String messageId,
    required File file,
    required String fileName,
    int? fileSizeBytes,
    int? durationSec,
    void Function(double progress)? onProgress,
  }) async {
    if (!isReady) return null;
    try {
      final storagePath = 'groups/$groupId/media/$messageId/$fileName';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await SafeRunner.runWithRetry<void>(
        maxAttempts: 2,
        task: (_) async {
          final uploadTask = ref.putFile(file);
          final sub = uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
            if (snap.totalBytes > 0) {
              onProgress?.call(snap.bytesTransferred / snap.totalBytes);
            }
          });
          try {
            await uploadTask;
          } finally {
            await sub.cancel();
          }
        },
      );
      final url = await ref.getDownloadURL();
      return MediaAttachment(
        fileName: fileName,
        localPath: file.path,
        remoteUrl: url,
        storagePath: storagePath,
        fileSizeBytes: fileSizeBytes,
        durationSec: durationSec,
      );
    } catch (e, s) {
      ErrorGuard.record('Storage送信エラー（ローカル保持継続）: $e', s);
      return null;
    }
  }
 
  Future<void> pushMessageToCloud(String groupId, ChatMessage msg) async {
    if (!isReady || uid == null) return;
    try {
      final fs = FirebaseFirestore.instance;
      if (msg.scheduledFor != null) {
        await fs.collection('scheduledMessages').doc(msg.id).set(<String, dynamic>{
          'groupId': groupId,
          'sendAt': Timestamp.fromDate(msg.scheduledFor!),
          'payload': msg.toJson()..['senderId'] = uid,
        });
      } else {
        final data = msg.toJson()..['senderId'] = msg.senderId ?? uid;
        data['createdAt'] = Timestamp.fromDate(msg.createdAt);
        if (msg.expiresAt != null) {
          data['expiresAt'] = Timestamp.fromDate(msg.expiresAt!);
        }
        await fs
            .collection('groups')
            .doc(groupId)
            .collection('messages')
            .doc(msg.id)
            .set(data, SetOptions(merge: true));
      }
    } catch (e, s) {
      ErrorGuard.record('メッセージクラウド同期エラー: $e', s);
    }
  }
 
  Future<void> updateMessageFieldsInCloud(
    String groupId,
    String messageId,
    JsonMap fields,
  ) async {
    if (!isReady || uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .doc(messageId)
          .set(fields, SetOptions(merge: true));
    } catch (e, s) {
      ErrorGuard.record('メッセージ差分同期エラー: $e', s);
    }
  }
 
  Future<void> createCallSignal({
    required String callId,
    required ChatGroup group,
    required String callerName,
    required bool isVideo,
  }) async {
    if (!isReady || uid == null) return;
    try {
      await syncGroupToCloud(group);
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .set(<String, dynamic>{
        'groupId': group.id,
        'groupName': group.name,
        'roomName': 'room_${group.id}_$callId',
        'callerId': uid,
        'callerName': callerName,
        'isVideo': isVideo,
        'ringtone': group.ringtone,
        'status': 'ringing',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, s) {
      ErrorGuard.record('着信シグナル送信エラー: $e', s);
    }
  }
 
  Future<void> updateCallStatus(String callId, String status) async {
    if (!isReady) return;
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .set(<String, dynamic>{'status': status}, SetOptions(merge: true));
    } catch (e, s) {
      ErrorGuard.record('通話ステータス更新エラー: $e', s);
    }
  }
 
  void dispose() {
    _groupSub?.cancel();
    for (final sub in _msgSubs.values) {
      sub.cancel();
    }
    _msgSubs.clear();
  }
}
