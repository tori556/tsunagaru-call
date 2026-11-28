import 'dart:async';
 
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
 
import '../models.dart';
import '../services/core_services.dart';
import '../services/webrtc_call_service.dart';
import '../store/app_store.dart';
 
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.store,
    required this.payload,
    required this.onAccept,
  });
 
  final AppStore store;
  final IncomingCallPayload payload;
  final void Function(bool withVideo) onAccept;
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1B18),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                children: <Widget>[
                  const SizedBox(height: 36),
                  Text(
                    payload.isVideo ? 'ビデオ着信' : '音声着信',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF1B8A5A),
                    child: Text(
                      initialLetter(payload.callerName),
                      style: const TextStyle(fontSize: 36, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    payload.callerName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'グループ: ${payload.groupName} ／ 着信音: ${payload.ringtone}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      FloatingActionButton.large(
                        heroTag: 'reject_call',
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        onPressed: () => store.clearIncomingCall(status: 'rejected'),
                        child: const Icon(Icons.call_end),
                      ),
                      const SizedBox(height: 8),
                      const Text('拒否', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                  Column(
                    children: <Widget>[
                      FloatingActionButton.large(
                        heroTag: 'accept_audio',
                        backgroundColor: const Color(0xFF1B8A5A),
                        foregroundColor: Colors.white,
                        onPressed: () => onAccept(false),
                        child: const Icon(Icons.call),
                      ),
                      const SizedBox(height: 8),
                      const Text('音声応答', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                  if (payload.isVideo)
                    Column(
                      children: <Widget>[
                        FloatingActionButton.large(
                          heroTag: 'accept_video',
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          onPressed: () => onAccept(true),
                          child: const Icon(Icons.videocam),
                        ),
                        const SizedBox(height: 8),
                        const Text('ビデオ応答', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
 
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.store,
    required this.group,
    required this.initialVideo,
    this.callId,
  });
 
  final AppStore store;
  final ChatGroup group;
  final bool initialVideo;
  final String? callId;
 
  @override
  State<CallScreen> createState() => _CallScreenState();
}
 
class _CallScreenState extends State<CallScreen> {
  lk.Room? _room;
  final WebRtcCallService _webrtc = WebRtcCallService();
  bool _micOn = true;
  late bool _camOn;
  late bool _noiseCancel;
  bool _connecting = false;
  late final String _activeCallId;
  String _status = '通話準備中...';
 
  @override
  void initState() {
    super.initState();
    _camOn = widget.initialVideo;
    _noiseCancel = widget.store.noiseCancellationEnabled;
    _activeCallId =
        widget.callId ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    if (widget.callId == null) {
      unawaited(
        widget.store.cloud.createCallSignal(
          callId: _activeCallId,
          group: widget.group,
          callerName: widget.store.myName,
          isVideo: widget.initialVideo,
        ),
      );
    }
    _connectCall();
  }
 
  Future<void> _connectCall() async {
    final url = widget.store.liveKitUrl.trim();
    final token = widget.store.liveKitToken.trim();
    if (url.isEmpty || token.isEmpty) {
      await _webrtc.start(
        callId: _activeCallId,
        isCaller: widget.callId == null,
        video: _camOn,
        micOn: _micOn,
        onStatus: (String s) {
          if (mounted) setState(() => _status = s);
        },
      );
      return;
    }
 
    setState(() {
      _connecting = true;
      _status = 'LiveKit ルームへ接続中...';
    });
 
    try {
      await SafeRunner.runWithRetry<void>(
        maxAttempts: 2,
        task: (_) async {
          final room = lk.Room(
            roomOptions: lk.RoomOptions(
              adaptiveStream: true,
              dynacast: true,
              defaultAudioCaptureOptions: lk.AudioCaptureOptions(
                noiseSuppression: _noiseCancel,
                echoCancellation: true,
                autoGainControl: true,
              ),
            ),
          );
          room.addListener(_onRoomUpdate);
          await room.connect(url, token);
          await room.localParticipant?.setMicrophoneEnabled(_micOn);
          await room.localParticipant?.setCameraEnabled(_camOn);
          _room = room;
        },
      );
      if (mounted) {
        setState(() {
          _connecting = false;
          _status = '接続完了（LiveKit SFU）';
        });
      }
    } catch (e, s) {
      ErrorGuard.record('LiveKit接続失敗（ローカル継続）: $e', s);
      if (mounted) {
        setState(() {
          _connecting = false;
          _status = '接続失敗のためローカル試用モードで継続';
        });
      }
    }
  }
 
  void _onRoomUpdate() {
    if (mounted) setState(() {});
  }
 
  Future<void> _toggleMic() async {
    setState(() => _micOn = !_micOn);
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    } catch (e, s) {
      ErrorGuard.record('マイク切替エラー: $e', s);
    }
  }
 
  Future<void> _toggleCam() async {
    if (!_camOn) {
      final ok = await NetworkGuard.confirmIfNotWifi(
        context,
        actionName: '通話中にカメラをオン',
        warnOnNonWifi: widget.store.warnOnNonWifi,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _camOn = !_camOn);
    try {
      await _room?.localParticipant?.setCameraEnabled(_camOn);
    } catch (e, s) {
      ErrorGuard.record('カメラ切替エラー: $e', s);
    }
  }
 
  Future<void> _openInCallChat() async {
    final textCtrl = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext bc) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(bc).viewInsets.bottom + 16,
          ),
          child: AnimatedBuilder(
            animation: widget.store,
            builder: (_, __) {
              final msgs = widget.group.messages.reversed.take(12).toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '通話中チャット・ファイル送信',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (widget.store.uploadProgress != null) ...<Widget>[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: widget.store.uploadProgress),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      reverse: true,
                      itemCount: msgs.length,
                      itemBuilder: (_, int i) {
                        final m = msgs[i];
                        return ListTile(
                          dense: true,
                          title: Text('${m.sender}: ${m.text}'),
                          subtitle: m.media != null
                              ? Text(
                                  '📎 ${m.media!.fileName} ${formatBytes(m.media!.fileSizeBytes)}',
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      IconButton(
                        tooltip: 'ファイル送信（形式・容量制限なし）',
                        icon: const Icon(Icons.attach_file),
                        onPressed: () async {
                          final res = await FilePicker.platform.pickFiles(
                            type: FileType.any,
                            withData: false,
                          );
                          if (res == null || res.files.isEmpty) return;
                          final f = res.files.single;
                          if (f.path == null || !bc.mounted) return;
                          final ok = await NetworkGuard.confirmIfNotWifi(
                            bc,
                            actionName: '通話中ファイル送信（${f.name}）',
                            warnOnNonWifi: widget.store.warnOnNonWifi,
                            fileSizeBytes: f.size,
                          );
                          if (!ok) return;
                          await widget.store.sendMessage(
                            widget.group.id,
                            text: 'ファイルを送信しました',
                            kind: 'file',
                            media: MediaAttachment(
                              fileName: f.name,
                              localPath: f.path,
                              fileSizeBytes: f.size,
                            ),
                          );
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: textCtrl,
                          decoration: const InputDecoration(
                            hintText: '通話中にメッセージ送信',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          if (textCtrl.text.trim().isEmpty) return;
                          widget.store.sendMessage(
                            widget.group.id,
                            text: textCtrl.text.trim(),
                          );
                          textCtrl.clear();
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      );
    } finally {
      disposeControllersSafely(<ChangeNotifier>[textCtrl]);
    }
  }
 
  lk.VideoTrack? _activeVideo(lk.Participant p) {
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is lk.VideoTrack && !pub.muted) return t;
    }
    return null;
  }
 
  @override
  void dispose() {
    unawaited(_webrtc.dispose());
    unawaited(widget.store.cloud.updateCallStatus(_activeCallId, 'ended'));
    _room?.removeListener(_onRoomUpdate);
    unawaited(_room?.disconnect());
    _room?.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    final liveParticipants = <lk.Participant>[
      if (_room?.localParticipant != null) _room!.localParticipant!,
      if (_room != null) ..._room!.remoteParticipants.values,
    ];
 
    return Scaffold(
      backgroundColor: const Color(0xFF121820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A232E),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.group.name, style: const TextStyle(fontSize: 16)),
            Text(_status, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          if (_connecting) const LinearProgressIndicator(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: liveParticipants.isNotEmpty
                  ? liveParticipants.length
                  : widget.group.members.length,
              itemBuilder: (_, int i) {
                if (liveParticipants.isNotEmpty) {
                  final p = liveParticipants[i];
                  final track = _activeVideo(p);
                  final label = p.name.isNotEmpty ? p.name : p.identity;
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF222F3D),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (track != null)
                          lk.VideoTrackRenderer(track)
                        else
                          Center(
                            child: CircleAvatar(
                              radius: 28,
                              child: Text(initialLetter(label)),
                            ),
                          ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0x99000000),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
 
                final member = widget.group.members[i];
                final isMe = member == widget.store.myName;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF222F3D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMe && _camOn ? Colors.greenAccent : Colors.white24,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CircleAvatar(radius: 28, child: Text(initialLetter(member))),
                      const SizedBox(height: 8),
                      Text(member, style: const TextStyle(color: Colors.white)),
                      Text(
                        isMe
                            ? '${_micOn ? "マイクON" : "ミュート"} / ${_camOn ? "カメラON" : "カメラOFF"}'
                            : '参加中',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  IconButton.filled(
                    onPressed: _toggleMic,
                    icon: Icon(_micOn ? Icons.mic : Icons.mic_off),
                    tooltip: 'マイク切替',
                  ),
                  IconButton.filled(
                    onPressed: _toggleCam,
                    icon: Icon(_camOn ? Icons.videocam : Icons.videocam_off),
                    tooltip: 'カメラ切替',
                  ),
                  IconButton.filled(
                    onPressed: () {
                      setState(() => _noiseCancel = !_noiseCancel);
                      widget.store.noiseCancellationEnabled = _noiseCancel;
                      widget.store.save();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('ノイズキャンセリング: ${_noiseCancel ? "ON" : "OFF"}'),
                        ),
                      );
                    },
                    icon: Icon(_noiseCancel ? Icons.noise_aware : Icons.hearing),
                    tooltip: 'ノイズキャンセリング',
                  ),
                  IconButton.filled(
                    onPressed: _openInCallChat,
                    icon: const Icon(Icons.chat),
                    tooltip: '通話中チャット・ファイル送信',
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.call_end),
                    tooltip: '通話終了',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
