import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import '../models/app_models.dart';
import 'firebase_service.dart';

class GroupParticipantTileData {
  final String id;
  final String name;
  final String emoji;
  final bool isLocal;
  final bool isSpeaking;
  final bool isMuted;
  final lk.VideoTrack? liveKitVideoTrack;
  final webrtc.RTCVideoRenderer? demoLocalRenderer;

  const GroupParticipantTileData({
    required this.id,
    required this.name,
    required this.emoji,
    required this.isLocal,
    this.isSpeaking = false,
    this.isMuted = false,
    this.liveKitVideoTrack,
    this.demoLocalRenderer,
  });
}

/// Phase 3: LiveKit SFU グループ音声/ビデオ通話サービス
/// LiveKit未設定時はローカルカメラ＆デモ参加者のマルチグリッドとして即動作します
class GroupCallService extends ChangeNotifier {
  final GroupChatRoom group;
  final bool initialVideo;

  GroupCallService({
    required this.group,
    required this.initialVideo,
  }) : isCameraOn = initialVideo;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  webrtc.MediaStream? _demoStream;
  webrtc.RTCVideoRenderer? _demoRenderer;

  bool isDemoMode = false;
  bool isConnected = false;
  bool isMuted = false;
  bool isCameraOn;
  bool isSpeakerOn = true;
  String statusLabel = 'グループ通話へ接続中…';
  bool _frontCamera = true;

  List<GroupParticipantTileData> get participants {
    final me = FirebaseService.instance.currentUser;
    if (isDemoMode) {
      final list = <GroupParticipantTileData>[
        GroupParticipantTileData(
          id: me?.uid ?? 'self',
          name: '${me?.displayName ?? '自分'}（あなた）',
          emoji: me?.emoji ?? '👨',
          isLocal: true,
          isSpeaking: !isMuted,
          isMuted: isMuted,
          demoLocalRenderer: isCameraOn ? _demoRenderer : null,
        ),
      ];
      for (final uid in group.memberUids) {
        if (uid == me?.uid) continue;
        final mName = group.memberNames[uid] ?? 'メンバー';
        list.add(GroupParticipantTileData(
          id: uid,
          name: mName,
          emoji: mName.contains('おばあ') ? '👵' : (mName.contains('おじ') ? '👴' : '😊'),
          isLocal: false,
          isSpeaking: uid == group.memberUids.last,
          isMuted: false,
        ));
      }
      return list;
    }

    if (_room == null) return const [];
    final tiles = <GroupParticipantTileData>[];
    final local = _room!.localParticipant;
    if (local != null) {
      lk.VideoTrack? localVid;
      for (final pub in local.videoTrackPublications) {
        if (pub.track is lk.VideoTrack && !pub.muted) {
          localVid = pub.track as lk.VideoTrack;
          break;
        }
      }
      tiles.add(GroupParticipantTileData(
        id: local.identity,
        name: '${local.name.isEmpty ? (me?.displayName ?? '自分') : local.name}（あなた）',
        emoji: me?.emoji ?? '👨',
        isLocal: true,
        isSpeaking: local.isSpeaking,
        isMuted: isMuted,
        liveKitVideoTrack: localVid,
      ));
    }

    for (final rp in _room!.remoteParticipants.values) {
      lk.VideoTrack? remoteVid;
      for (final pub in rp.videoTrackPublications) {
        if (pub.subscribed && pub.track is lk.VideoTrack && !pub.muted) {
          remoteVid = pub.track as lk.VideoTrack;
          break;
        }
      }
      final muted = rp.audioTrackPublications.every((p) => p.muted);
      tiles.add(GroupParticipantTileData(
        id: rp.identity,
        name: rp.name.isEmpty ? rp.identity : rp.name,
        emoji: '👤',
        isLocal: false,
        isSpeaking: rp.isSpeaking,
        isMuted: muted,
        liveKitVideoTrack: remoteVid,
      ));
    }
    return tiles;
  }

  Future<void> connect() async {
    final fb = FirebaseService.instance;
    final session = await fb.startOrJoinGroupCall(
      group: group,
      isVideo: initialVideo,
    );

    if (!fb.isLiveKitConfigured) {
      await _startDemoGroupCall();
      return;
    }

    try {
      statusLabel = 'LiveKitトークン取得中…';
      notifyListeners();

      final me = fb.currentUser!;
      final res = await http.post(
        Uri.parse(fb.liveKitTokenEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomName': session.roomName,
          'identity': me.uid,
          'name': me.displayName,
        }),
      );
      if (res.statusCode != 200) {
        throw Exception('トークン発行エラー (${res.statusCode})');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final token = (body['token'] ?? '').toString();
      if (token.isEmpty) throw Exception('空のLiveKitトークン');

      statusLabel = 'グループ通話ルームへ接続中…';
      notifyListeners();

      _room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      _listener = _room!.createListener();
      _listener!.on<lk.RoomEvent>((_) => notifyListeners());

      await _room!.connect(fb.liveKitUrl, token);
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      if (initialVideo) {
        await _room!.localParticipant?.setCameraEnabled(true);
      }
      await lk.Hardware.instance.setSpeakerphoneOn(true);

      isConnected = true;
      statusLabel = 'グループ通話中（LiveKit SFU）';
      notifyListeners();
    } catch (e) {
      debugPrint('LiveKit connect failed, fallback to demo: $e');
      await _startDemoGroupCall();
    }
  }

  Future<void> _startDemoGroupCall() async {
    isDemoMode = true;
    try {
      if (initialVideo) {
        _demoRenderer = webrtc.RTCVideoRenderer();
        await _demoRenderer!.initialize();
      }
      _demoStream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': initialVideo ? {'facingMode': 'user'} : false,
      });
      if (_demoRenderer != null) {
        _demoRenderer!.srcObject = _demoStream;
      }
    } catch (e) {
      debugPrint('Demo group call media warning: $e');
    }
    isConnected = true;
    statusLabel = 'グループ通話中（デモ）';
    notifyListeners();
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    if (isDemoMode) {
      for (final t in _demoStream?.getAudioTracks() ?? const []) {
        t.enabled = !isMuted;
      }
    } else {
      await _room?.localParticipant?.setMicrophoneEnabled(!isMuted);
    }
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    isCameraOn = !isCameraOn;
    if (isDemoMode) {
      if (isCameraOn && _demoRenderer == null) {
        _demoRenderer = webrtc.RTCVideoRenderer();
        await _demoRenderer!.initialize();
        _demoStream = await webrtc.navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': {'facingMode': _frontCamera ? 'user' : 'environment'},
        });
        _demoRenderer!.srcObject = _demoStream;
      } else {
        for (final t in _demoStream?.getVideoTracks() ?? const []) {
          t.enabled = isCameraOn;
        }
      }
    } else {
      await _room?.localParticipant?.setCameraEnabled(isCameraOn);
    }
    notifyListeners();
  }

  Future<void> flipCamera() async {
    if (!isCameraOn) return;
    _frontCamera = !_frontCamera;
    if (isDemoMode) {
      final tracks = _demoStream?.getVideoTracks() ?? const [];
      if (tracks.isNotEmpty) {
        await webrtc.Helper.switchCamera(tracks.first);
      }
    } else {
      final pubs = _room?.localParticipant?.videoTrackPublications;
      final pub = (pubs != null && pubs.isNotEmpty) ? pubs.first : null;
      final track = pub?.track;
      if (track is lk.LocalVideoTrack) {
        await track.restartTrack(
          lk.CameraCaptureOptions(
            cameraPosition:
                _frontCamera ? lk.CameraPosition.front : lk.CameraPosition.back,
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn = !isSpeakerOn;
    try {
      if (isDemoMode) {
        await webrtc.Helper.setSpeakerphoneOn(isSpeakerOn);
      } else {
        await lk.Hardware.instance.setSpeakerphoneOn(isSpeakerOn);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> disconnect() async {
    await FirebaseService.instance.leaveGroupCall(group);
    await _listener?.dispose();
    _listener = null;
    try {
      await _room?.disconnect();
      await _room?.dispose();
    } catch (_) {}
    _room = null;

    if (_demoStream != null) {
      for (final t in _demoStream!.getTracks()) {
        await t.stop();
      }
      await _demoStream!.dispose();
      _demoStream = null;
    }
    if (_demoRenderer != null) {
      await _demoRenderer!.dispose();
      _demoRenderer = null;
    }
  }
}
