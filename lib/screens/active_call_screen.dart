import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/app_models.dart';
import '../services/call_signaling_service.dart';
import '../services/firebase_service.dart';

class ActiveCallScreen extends StatefulWidget {
  final ContactItem? outgoingCallee;
  final IncomingCallPayload? incomingPayload;
  final bool isVideo;

  const ActiveCallScreen({
    super.key,
    this.outgoingCallee,
    this.incomingPayload,
    required this.isVideo,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  late final CallSignalingService _signaling;
  bool _connected = false;
  bool _muted = false;
  bool _speakerOn = false;
  late bool _camOn;
  bool _hasRemoteVideo = false;
  int _seconds = 0;
  Timer? _timer;
  bool _closing = false;
  String _networkLabel = '接続中…';

  String get _peerName =>
      widget.outgoingCallee?.name ?? widget.incomingPayload?.callerName ?? '通話相手';
  String get _peerEmoji =>
      widget.outgoingCallee?.emoji ?? widget.incomingPayload?.callerEmoji ?? '📞';
  ContactCategory get _category =>
      widget.outgoingCallee?.category ??
      widget.incomingPayload?.category ??
      ContactCategory.other;

  @override
  void initState() {
    super.initState();
    _camOn = widget.isVideo;
    _speakerOn = widget.isVideo;
    _signaling = CallSignalingService(
      onRemoteStream: (stream) {
        if (!mounted) return;
        setState(() {
          _remoteRenderer.srcObject = stream;
          _hasRemoteVideo = stream.getVideoTracks().isNotEmpty;
        });
      },
      onCallConnected: () {
        if (!mounted || _connected) return;
        setState(() => _connected = true);
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
      },
      onCallEnded: () => _endCall(notifyFirestore: false),
      onNetworkStatusChanged: (label) {
        if (mounted) setState(() => _networkLabel = label);
      },
    );
    _boot();
  }

  Future<void> _boot() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    try {
      if (widget.outgoingCallee != null) {
        await _signaling.startOutgoingCall(
          callee: widget.outgoingCallee!,
          isVideo: widget.isVideo,
        );
      } else if (widget.incomingPayload != null) {
        await _signaling.answerIncomingCall(widget.incomingPayload!);
      }
      if (mounted && _signaling.localStream != null) {
        setState(() {
          _localRenderer.srcObject = _signaling.localStream;
        });
      }
      await _signaling.setSpeakerphone(_speakerOn);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('マイク・カメラの起動に失敗しました: $e')),
        );
        _endCall(notifyFirestore: false);
      }
    }
  }

  String _formatDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCall({bool notifyFirestore = true}) async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _signaling.hangup(notifyFirestore: notifyFirestore);

    FirebaseService.instance.addCallHistory(CallHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      peerName: _peerName,
      peerEmoji: _peerEmoji,
      targetUid: widget.outgoingCallee?.targetUid ??
          widget.incomingPayload?.callerUid ??
          '',
      category: _category,
      isVideo: widget.isVideo,
      isOutgoing: widget.outgoingCallee != null,
      isMissed: !_connected,
      durationSec: _seconds,
      createdAt: DateTime.now(),
    ));

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = _category;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _connected ? _networkLabel : '呼び出し中…',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _formatDuration(_seconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_hasRemoteVideo)
                        RTCVideoView(
                          _remoteRenderer,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      else
                        Container(
                          color: const Color(0xFF1E293B),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cat.bgColor,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '${cat.emoji} ${cat.label}',
                                  style: TextStyle(
                                    color: cat.fgColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              CircleAvatar(
                                radius: 56,
                                backgroundColor:
                                    const Color(0xFFF97316).withOpacity(0.25),
                                child: Text(
                                  _peerEmoji,
                                  style: const TextStyle(fontSize: 52),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _peerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.isVideo ? 'ビデオ通話' : '音声通話',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      if (widget.isVideo && _camOn)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          width: 112,
                          height: 160,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 2,
                                ),
                              ),
                              child: RTCVideoView(
                                _localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallControlButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: _muted ? 'ミュート中' : 'マイク',
                    activeOff: _muted,
                    onTap: () {
                      setState(() => _muted = !_muted);
                      _signaling.setMuted(_muted);
                    },
                  ),
                  _CallControlButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.hearing,
                    label: _speakerOn ? 'スピーカー' : '受話口',
                    onTap: () {
                      setState(() => _speakerOn = !_speakerOn);
                      _signaling.setSpeakerphone(_speakerOn);
                    },
                  ),
                  if (widget.isVideo) ...[
                    _CallControlButton(
                      icon: _camOn ? Icons.videocam : Icons.videocam_off,
                      label: _camOn ? 'カメラON' : 'カメラOFF',
                      activeOff: !_camOn,
                      onTap: () {
                        setState(() => _camOn = !_camOn);
                        _signaling.setCameraEnabled(_camOn);
                      },
                    ),
                    _CallControlButton(
                      icon: Icons.cameraswitch,
                      label: '反転',
                      onTap: () => _signaling.switchCamera(),
                    ),
                  ],
                  _CallControlButton(
                    icon: Icons.call_end,
                    label: '終了',
                    isHangup: true,
                    onTap: () => _endCall(notifyFirestore: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool activeOff;
  final bool isHangup;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.activeOff = false,
    this.isHangup = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isHangup
        ? const Color(0xFFDC2626)
        : (activeOff ? const Color(0x66EF4444) : Colors.white12);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 64,
        height: 68,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
