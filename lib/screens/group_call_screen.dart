import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import '../models/app_models.dart';
import '../services/firebase_service.dart';
import '../services/group_call_service.dart';

class GroupCallScreen extends StatefulWidget {
  final GroupChatRoom group;
  final bool isVideo;

  const GroupCallScreen({
    super.key,
    required this.group,
    required this.isVideo,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  late final GroupCallService _service;
  Timer? _timer;
  int _seconds = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _service = GroupCallService(
      group: widget.group,
      initialVideo: widget.isVideo,
    );
    _service.addListener(_onChanged);
    _service.connect().then((_) {
      if (!mounted) return;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _fmt(int s) {
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    await _service.disconnect();
    FirebaseService.instance.addCallHistory(CallHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      peerName: '${widget.group.name}（グループ）',
      peerEmoji: widget.group.emoji,
      targetUid: widget.group.id,
      category: widget.group.category,
      isVideo: widget.isVideo,
      isOutgoing: true,
      durationSec: _seconds,
      createdAt: DateTime.now(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.removeListener(_onChanged);
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _service.participants;
    final crossAxisCount = tiles.length <= 2 ? 1 : (tiles.length <= 4 ? 2 : 3);
    final cat = widget.group.category;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
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
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.group.name} (${tiles.length}人)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _service.statusLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _fmt(_seconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Participant Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.builder(
                  itemCount: tiles.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: tiles.length <= 2 ? 1.25 : 0.85,
                  ),
                  itemBuilder: (context, idx) {
                    final t = tiles[idx];
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: t.isSpeaking
                              ? const Color(0xFF4ADE80)
                              : Colors.white12,
                          width: t.isSpeaking ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (t.liveKitVideoTrack != null)
                            lk.VideoTrackRenderer(
                              t.liveKitVideoTrack!,
                            )
                          else if (t.demoLocalRenderer != null)
                            webrtc.RTCVideoView(
                              t.demoLocalRenderer!,
                              mirror: true,
                              objectFit: webrtc.RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            )
                          else
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 34,
                                  backgroundColor:
                                      const Color(0xFFF97316).withOpacity(0.25),
                                  child: Text(
                                    t.emoji,
                                    style: const TextStyle(fontSize: 34),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (t.isSpeaking)
                                  const Text(
                                    '話し中…',
                                    style: TextStyle(
                                      color: Color(0xFF4ADE80),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),

                          // Name Tag Overlay
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    t.isMuted ? Icons.mic_off : Icons.mic,
                                    size: 14,
                                    color: t.isMuted
                                        ? const Color(0xFFF87171)
                                        : const Color(0xFF4ADE80),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      t.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // Bottom Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _GrpCtrlBtn(
                    icon: _service.isMuted ? Icons.mic_off : Icons.mic,
                    label: _service.isMuted ? 'ミュート' : 'マイク',
                    off: _service.isMuted,
                    onTap: _service.toggleMute,
                  ),
                  _GrpCtrlBtn(
                    icon: _service.isSpeakerOn
                        ? Icons.volume_up
                        : Icons.hearing,
                    label: _service.isSpeakerOn ? 'スピーカー' : '受話口',
                    onTap: _service.toggleSpeaker,
                  ),
                  _GrpCtrlBtn(
                    icon: _service.isCameraOn
                        ? Icons.videocam
                        : Icons.videocam_off,
                    label: _service.isCameraOn ? 'カメラON' : 'カメラOFF',
                    off: !_service.isCameraOn,
                    onTap: _service.toggleCamera,
                  ),
                  _GrpCtrlBtn(
                    icon: Icons.cameraswitch,
                    label: '反転',
                    onTap: _service.flipCamera,
                  ),
                  _GrpCtrlBtn(
                    icon: Icons.call_end,
                    label: '退出',
                    hangup: true,
                    onTap: _leave,
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

class _GrpCtrlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool off;
  final bool hangup;
  final VoidCallback onTap;

  const _GrpCtrlBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.off = false,
    this.hangup = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = hangup
        ? const Color(0xFFDC2626)
        : (off ? const Color(0x66EF4444) : Colors.white12);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 60,
        height: 64,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
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
