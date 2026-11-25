import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../models/app_models.dart';
import 'firebase_service.dart';
import 'push_callkit_incoming.dart';

/// Phase 4: TURN自動中継＆接続品質監視対応 WebRTC シグナリング
class CallSignalingService {
  CallSignalingService({
    required this.onRemoteStream,
    required this.onCallConnected,
    required this.onCallEnded,
    this.onNetworkStatusChanged,
  });

  final void Function(MediaStream stream) onRemoteStream;
  final VoidCallback onCallConnected;
  final VoidCallback onCallEnded;
  final void Function(String statusLabel)? onNetworkStatusChanged;

  RTCPeerConnection? _pc;
  MediaStream? localStream;
  String? currentCallId;
  bool isDemo = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _candidatesSub;

  Future<Map<String, dynamic>> _buildRtcConfig() async {
    final iceServers = await FirebaseService.instance.fetchIceServers();
    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };
  }

  void _attachIceMonitor(RTCPeerConnection pc) {
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          onNetworkStatusChanged?.call('経路確認中…');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          final hasTurn = FirebaseService.instance.isTurnConfigured;
          onNetworkStatusChanged?.call(hasTurn ? '🟢 接続良好 (TURN対応)' : '🟢 接続良好');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          onNetworkStatusChanged?.call('🟡 回線不安定・再接続中');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          onNetworkStatusChanged?.call('🔴 接続失敗（TURN設定を確認）');
          break;
        default:
          break;
      }
    };
  }

  Future<MediaStream> openLocalMedia({required bool video}) async {
    final constraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 720},
              'height': {'ideal': 1280},
            }
          : false,
    };
    localStream = await navigator.mediaDevices.getUserMedia(constraints);
    return localStream!;
  }

  Future<String> startOutgoingCall({
    required ContactItem callee,
    required bool isVideo,
  }) async {
    final fb = FirebaseService.instance;
    final me = fb.currentUser!;
    currentCallId = const Uuid().v4();

    await openLocalMedia(video: isVideo);

    if (!fb.firebaseReady) {
      isDemo = true;
      onNetworkStatusChanged?.call('🧪 デモ通話');
      Future.delayed(const Duration(seconds: 1), onCallConnected);
      return currentCallId!;
    }

    final callRef =
        FirebaseFirestore.instance.collection('calls').doc(currentCallId);
    final offerCandidatesRef = callRef.collection('offerCandidates');
    final answerCandidatesRef = callRef.collection('answerCandidates');

    final rtcConfig = await _buildRtcConfig();
    _pc = await createPeerConnection(rtcConfig);
    _attachIceMonitor(_pc!);

    for (final track in localStream!.getTracks()) {
      await _pc!.addTrack(track, localStream!);
    }

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream(event.streams.first);
        onCallConnected();
      }
    };

    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate != null) {
        offerCandidatesRef.add(c.toMap());
      }
    };

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await callRef.set({
      'callerUid': me.uid,
      'callerName': me.displayName,
      'callerEmoji': me.emoji,
      'calleeUid': callee.targetUid,
      'category': callee.category.id,
      'isVideo': isVideo,
      'status': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'createdAt': FieldValue.serverTimestamp(),
    });

    _callDocSub = callRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      final status = data['status']?.toString();
      if (status == 'ended' || status == 'declined') {
        onCallEnded();
        return;
      }
      if (data['answer'] != null && await _pc?.getRemoteDescription() == null) {
        final ans = Map<String, dynamic>.from(data['answer'] as Map);
        await _pc?.setRemoteDescription(
          RTCSessionDescription(ans['sdp']?.toString(), ans['type']?.toString()),
        );
      }
    });

    _candidatesSub = answerCandidatesRef.snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d != null) {
            _pc?.addCandidate(RTCIceCandidate(
              d['candidate']?.toString(),
              d['sdpMid']?.toString(),
              (d['sdpMLineIndex'] as num?)?.toInt(),
            ));
          }
        }
      }
    });

    return currentCallId!;
  }

  Future<void> answerIncomingCall(IncomingCallPayload payload) async {
    currentCallId = payload.callId;
    await openLocalMedia(video: payload.isVideo);

    if (payload.isDemo || !FirebaseService.instance.firebaseReady) {
      isDemo = true;
      onNetworkStatusChanged?.call('🧪 デモ通話');
      onCallConnected();
      return;
    }

    final callRef =
        FirebaseFirestore.instance.collection('calls').doc(payload.callId);
    final callSnap = await callRef.get();
    final callData = callSnap.data();
    if (callData == null || callData['offer'] == null) {
      onCallEnded();
      return;
    }

    final offerCandidatesRef = callRef.collection('offerCandidates');
    final answerCandidatesRef = callRef.collection('answerCandidates');

    final rtcConfig = await _buildRtcConfig();
    _pc = await createPeerConnection(rtcConfig);
    _attachIceMonitor(_pc!);

    for (final track in localStream!.getTracks()) {
      await _pc!.addTrack(track, localStream!);
    }

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream(event.streams.first);
        onCallConnected();
      }
    };

    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate != null) {
        answerCandidatesRef.add(c.toMap());
      }
    };

    final offer = Map<String, dynamic>.from(callData['offer'] as Map);
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offer['sdp']?.toString(), offer['type']?.toString()),
    );

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await callRef.update({
      'status': 'answered',
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'answeredAt': FieldValue.serverTimestamp(),
    });

    _candidatesSub = offerCandidatesRef.snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d != null) {
            _pc?.addCandidate(RTCIceCandidate(
              d['candidate']?.toString(),
              d['sdpMid']?.toString(),
              (d['sdpMLineIndex'] as num?)?.toInt(),
            ));
          }
        }
      }
    });

    _callDocSub = callRef.snapshots().listen((snap) {
      final status = snap.data()?['status']?.toString();
      if (status == 'ended' || status == 'declined') {
        onCallEnded();
      }
    });
  }

  void setMuted(bool muted) {
    final tracks = localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
  }

  void setCameraEnabled(bool enabled) {
    final tracks = localStream?.getVideoTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? const [];
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  Future<void> setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {}
  }

  Future<void> hangup({bool notifyFirestore = true}) async {
    await _callDocSub?.cancel();
    await _candidatesSub?.cancel();

    if (notifyFirestore &&
        !isDemo &&
        currentCallId != null &&
        FirebaseService.instance.firebaseReady) {
      try {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(currentCallId)
            .update({'status': 'ended'});
      } catch (_) {}
    }

    if (currentCallId != null) {
      await PushCallKitService.instance.endCallKit(currentCallId!);
    }

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;

    if (localStream != null) {
      for (final t in localStream!.getTracks()) {
        await t.stop();
      }
      await localStream!.dispose();
      localStream = null;
    }
  }
}
