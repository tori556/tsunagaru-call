import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';
import '../models/ringtone_prefs.dart';

/// バックグラウンド / ロック画面で着信FCMを受信した際のトップレベルハンドラ
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] == 'incoming_call') {
    await PushCallKitService.showNativeIncomingCallFromMap(message.data);
  }
}

/// Phase 4: iOS PushKit VoIP + Android 全画面着信 + カテゴリ別カスタム着信音サービス
class PushCallKitService {
  PushCallKitService._();
  static final PushCallKitService instance = PushCallKitService._();

  final StreamController<IncomingCallPayload> _acceptedCtrl =
      StreamController<IncomingCallPayload>.broadcast();
  final StreamController<String> _declinedCtrl =
      StreamController<String>.broadcast();

  Stream<IncomingCallPayload> get onCallAccepted => _acceptedCtrl.stream;
  Stream<String> get onCallDeclined => _declinedCtrl.stream;

  String? fcmToken;
  String? voipToken;
  bool _initialized = false;

  Future<String?> initialize({
    required bool firebaseReady,
    required void Function(String token) onTokenUpdated,
    void Function(String voipToken)? onVoipTokenUpdated,
  }) async {
    if (!_initialized) {
      _initialized = true;
      _listenCallKitEvents();
    }

    try {
      final rawVoip = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (rawVoip is String && rawVoip.isNotEmpty) {
        voipToken = rawVoip;
        onVoipTokenUpdated?.call(rawVoip);
        debugPrint('iOS PushKit VoIP Token synced');
      }
    } catch (_) {}

    if (!firebaseReady) return null;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      fcmToken = await messaging.getToken();
      if (fcmToken != null && fcmToken!.isNotEmpty) {
        onTokenUpdated(fcmToken!);
      }

      messaging.onTokenRefresh.listen((newToken) {
        fcmToken = newToken;
        onTokenUpdated(newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        if (msg.data['type'] == 'incoming_call') {
          showNativeIncomingCallFromMap(msg.data);
        }
      });
    } catch (e) {
      debugPrint('PushCallKitService init warning: $e');
    }

    return fcmToken;
  }

  void _listenCallKitEvents() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      final extra = Map<String, dynamic>.from(
        (event.body?['extra'] as Map?) ?? const {},
      );
      final callId = (event.body?['id'] ?? extra['callId'] ?? '').toString();

      switch (event.event) {
        case Event.actionCallAccept:
          final payload = IncomingCallPayload(
            callId: callId,
            callerUid: (extra['callerUid'] ?? '').toString(),
            callerName: (extra['callerName'] ?? '着信相手').toString(),
            callerEmoji: (extra['callerEmoji'] ?? '📞').toString(),
            category: ContactCategory.fromId(extra['category']?.toString()),
            isVideo: extra['isVideo'] == '1' || extra['isVideo'] == true,
            isDemo: extra['isDemo'] == '1' || extra['isDemo'] == true,
          );
          _acceptedCtrl.add(payload);
          break;
        case Event.actionCallDecline:
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          if (callId.isNotEmpty) {
            _declinedCtrl.add(callId);
          }
          break;
        default:
          break;
      }
    });
  }

  /// カテゴリ別のカスタム着信音を読み込み、ネイティブ着信画面を表示
  static Future<void> showNativeIncomingCall(IncomingCallPayload payload) async {
    final cat = payload.category;

    RingtoneConfig config = RingtoneConfig.defaults();
    try {
      final prefs = await SharedPreferences.getInstance();
      config = RingtoneConfig.fromJsonString(
        prefs.getString('ringtone_config_json'),
      );
    } catch (_) {}

    final catSetting = config.forCategory(cat);
    final androidRingtone = catSetting.preset.androidRawName;
    final iosRingtone = catSetting.preset.iosFileName;

    final params = CallKitParams(
      id: payload.callId,
      nameCaller: '${cat.emoji}【${cat.label}】${payload.callerName}',
      appName: 'つながる電話',
      handle: payload.isVideo ? 'ビデオ通話の着信' : '音声通話の着信',
      type: payload.isVideo ? 1 : 0,
      duration: 35000,
      textAccept: '応答',
      textDecline: '拒否',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: '不在着信があります',
        callbackText: '折り返す',
      ),
      extra: <String, dynamic>{
        'callId': payload.callId,
        'callerUid': payload.callerUid,
        'callerName': payload.callerName,
        'callerEmoji': payload.callerEmoji,
        'category': cat.id,
        'isVideo': payload.isVideo ? '1' : '0',
        'isDemo': payload.isDemo ? '1' : '0',
      },
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: androidRingtone,
        backgroundColor: '#1E293B',
        actionColor: '#16A34A',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: '着信通知（${cat.label}）',
        missedCallNotificationChannelName: '不在着信',
        isShowFullLockedScreen: true,
      ),
      ios: IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: iosRingtone,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  static Future<void> showNativeIncomingCallFromMap(
    Map<String, dynamic> data,
  ) async {
    final payload = IncomingCallPayload(
      callId: (data['callId'] ?? DateTime.now().millisecondsSinceEpoch.toString())
          .toString(),
      callerUid: (data['callerUid'] ?? '').toString(),
      callerName: (data['callerName'] ?? '着信相手').toString(),
      callerEmoji: (data['callerEmoji'] ?? '📞').toString(),
      category: ContactCategory.fromId(data['category']?.toString()),
      isVideo: data['isVideo'] == '1' || data['isVideo'] == true,
      isDemo: data['isDemo'] == '1' || data['isDemo'] == true,
    );
    await showNativeIncomingCall(payload);
  }

  Future<void> endCallKit(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {}
  }
}
