import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcCallService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<DocumentSnapshot>>? _docSub;
  final Set<String> _addedCandidates = <String>{};
  bool _remoteDescSet = false;
  bool _answerCreated = false;
  bool _disposed = false;

  Future<void> start({
    required String callId,
    required bool isCaller,
    required bool video,
    required bool micOn,
    required void Function(String status) onStatus,
  }) async {
    try {
      onStatus('マイク・音声接続を準備中...');
      _localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': video,
      });
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = micOn;
      }

      final config = <String, dynamic>{
        'iceServers': >[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
          <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
        ],
      };

      _pc = await createPeerConnection(config);
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      _pc!.onConnectionState = (RTCPeerConnectionState state) {
        if (_disposed) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          Helper.setSpeakerphoneOn(true);
          onStatus('通話中（音声接続完了）');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          onStatus('音声接続に失敗しました');
        }
      };

      final callDoc = FirebaseFirestore.instance.collection('calls').doc(callId);
      final myCandField = isCaller ? 'callerCandidates' : 'calleeCandidates';
      final peerCandField = isCaller ? 'calleeCandidates' : 'callerCandidates';

      _pc!.onIceCandidate = (RTCIceCandidate cand) {
        if (cand.candidate == null || _disposed) return;
        callDoc.set(<String, dynamic>{
          myCandField: FieldValue.arrayUnion(>[
            <String, dynamic>{
              'candidate': cand.candidate,
              'sdpMid': cand.sdpMid,
              'sdpMLineIndex': cand.sdpMLineIndex,
            },
          ]),
        }, SetOptions(merge: true));
      };

      if (isCaller) {
        final offer = await _pc!.createOffer(<String, dynamic>{
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': video ? 1 : 0,
        });
        await _pc!.setLocalDescription(offer);
        await callDoc.set(<String, dynamic>{
          'offer': <String, dynamic>{'sdp': offer.sdp, 'type': offer.type},
        }, SetOptions(merge: true));
        onStatus('相手の応答を待っています...');
      } else {
        onStatus('発信者と音声を接続中...');
      }

      _docSub = callDoc.snapshots().listen((snap) async {
        if (_disposed || !snap.exists) return;
        final data = snap.data();
        if (data == null) return;

        if (!isCaller && !_answerCreated && data['offer'] is Map) {
          _answerCreated = true;
          final offerMap = Map<String, dynamic>.from(data['offer'] as Map);
          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              offerMap['sdp']?.toString(),
              offerMap['type']?.toString(),
            ),
          );
          _remoteDescSet = true;
          final answer = await _pc!.createAnswer(<String, dynamic>{
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': video ? 1 : 0,
          });
          await _pc!.setLocalDescription(answer);
          await callDoc.set(<String, dynamic>{
            'answer': <String, dynamic>{'sdp': answer.sdp, 'type': answer.type},
          }, SetOptions(merge: true));
        }

        if (isCaller && !_remoteDescSet && data['answer'] is Map) {
          final ansMap = Map<String, dynamic>.from(data['answer'] as Map);
          await _pc!.setRemoteDescription(
            RTCSessionDescription(
              ansMap['sdp']?.toString(),
              ansMap['type']?.toString(),
            ),
          );
          _remoteDescSet = true;
        }

        if (_remoteDescSet && data[peerCandField] is List) {
          for (final item in data[peerCandField] as List) {
            if (item is! Map) continue;
            final candStr = item['candidate']?.toString() ?? '';
            if (candStr.isEmpty || !_addedCandidates.add(candStr)) continue;
            await _pc!.addCandidate(
              RTCIceCandidate(
                candStr,
                item['sdpMid']?.toString(),
                item['sdpMLineIndex'] is int ? item['sdpMLineIndex'] as int : 0,
              ),
            );
          }
        }
      });
    } catch (e) {
      if (!_disposed) {
        onStatus('音声接続エラー: $e');
      }
    }
  }

  void setMicEnabled(bool enabled) {
    final stream = _localStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = enabled;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _docSub?.cancel();
    _docSub = null;
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    await _pc?.close();
    _pc = null;
  }
}
