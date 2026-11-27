import 'dart:async';
import 'dart:io';
 
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
 
import '../models.dart';
import '../services/core_services.dart';
import '../store/app_store.dart';
 
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.store,
    required this.groupId,
  });
 
  final AppStore store;
  final String groupId;
 
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
 
class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSub;
 
  bool _searching = false;
  bool _silentMode = false;
  bool _isTyping = false;
  bool _recording = false;
  DateTime? _recordStartedAt;
  String? _playingMessageId;
  int? _expireOverride;
  ChatMessage? _replyTarget;
 
  ChatGroup? get _group => widget.store.findGroup(widget.groupId);
 
  @override
  void initState() {
    super.initState();
    final g = _group;
    if (g != null && g.draft.isNotEmpty) {
      _inputCtrl.text = g.draft;
    }
    _playerSub = _audioPlayer.playerStateStream.listen((PlayerState st) {
      if (st.processingState == ProcessingState.completed && mounted) {
        setState(() => _playingMessageId = null);
      }
    });
  }
 
  @override
  void dispose() {
    _playerSub?.cancel();
    _inputCtrl.dispose();
    _searchCtrl.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
 
  Future<void> _sendNow({Duration? delay}) async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    await widget.store.sendMessage(
      widget.groupId,
      text: text,
      expireHoursOverride: _expireOverride,
      silent: _silentMode,
      replyToId: _replyTarget?.id,
      replyPreview: _replyTarget != null
          ? '${_replyTarget!.sender}: ${_replyTarget!.text}'
          : null,
      scheduleDelay: delay,
    );
    _inputCtrl.clear();
    if (!mounted) return;
    setState(() {
      _replyTarget = null;
      _isTyping = false;
    });
    if (delay != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${delay.inMinutes}分後に予約送信をセットしました')),
      );
    }
  }
 
  Future<void> _toggleVoiceRecord() async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        final sec = _recordStartedAt != null
            ? DateTime.now().difference(_recordStartedAt!).inSeconds.clamp(1, 600)
            : 1;
        setState(() {
          _recording = false;
          _recordStartedAt = null;
        });
        if (path != null && mounted) {
          final size = await File(path).length();
          await widget.store.sendMessage(
            widget.groupId,
            text: '🎤 ボイスメッセージ（$sec秒）',
            kind: 'voice',
            expireHoursOverride: _expireOverride,
            silent: _silentMode,
            media: MediaAttachment(
              fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
              localPath: path,
              fileSizeBytes: size,
              durationSec: sec,
            ),
          );
        }
      } else {
        if (!await _recorder.hasPermission()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('マイク権限を許可してください')),
            );
          }
          return;
        }
        final dir = await getTemporaryDirectory();
        final outPath =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: outPath,
        );
        setState(() {
          _recording = true;
          _recordStartedAt = DateTime.now();
        });
      }
    } catch (e, s) {
      ErrorGuard.record('ボイス録音エラー: $e', s);
      if (mounted) setState(() => _recording = false);
    }
  }
 
  Future<void> _playVoice(ChatMessage msg) async {
    try {
      if (_playingMessageId == msg.id) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }
      final media = msg.media;
      if (media == null) return;
      if (media.localPath != null && File(media.localPath!).existsSync()) {
        await _audioPlayer.setFilePath(media.localPath!);
      } else if (media.remoteUrl != null) {
        await _audioPlayer.setUrl(media.remoteUrl!);
      } else {
        return;
      }
      setState(() => _playingMessageId = msg.id);
      unawaited(_audioPlayer.play());
    } catch (e, s) {
      ErrorGuard.record('ボイス再生エラー: $e', s);
      if (mounted) setState(() => _playingMessageId = null);
    }
  }
 
  void _openStampPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bc) => SafeArea(
        child: GridView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: stampCatalog.length,
          itemBuilder: (_, int i) {
            final st = stampCatalog[i];
            return InkWell(
              onTap: () {
                Navigator.of(bc).pop();
                widget.store.sendMessage(
                  widget.groupId,
                  text: '${st.emoji} ${st.label}',
                  kind: 'stamp',
                  expireHoursOverride: _expireOverride,
                  silent: _silentMode,
                );
              },
              child: Card(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(st.emoji, style: const TextStyle(fontSize: 28)),
                    Text(
                      st.label,
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
 
  void _openAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('写真を送信'),
              onTap: () {
                Navigator.of(bc).pop();
                _pickAndSendPhoto(viewOnce: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.looks_one, color: Colors.deepOrange),
              title: const Text('写真を「1回だけ表示」で送信'),
              subtitle: const Text('表示完了して閉じると再表示できなくなります'),
              onTap: () {
                Navigator.of(bc).pop();
                _pickAndSendPhoto(viewOnce: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.movie),
              title: const Text('軽量動画メッセージ（最大15秒）'),
              onTap: () {
                Navigator.of(bc).pop();
                _pickAndSendShortVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Color(0xFF1B8A5A)),
              title: const Text('PDF・あらゆるファイルを送信（容量制限なし）'),
              subtitle: const Text('Wi-Fi外ではサイズ付き確認ポップアップを表示'),
              onTap: () {
                Navigator.of(bc).pop();
                _pickAndSendAnyFile();
              },
            ),
          ],
        ),
      ),
    );
  }
 
  Future<void> _pickAndSendPhoto({required bool viewOnce}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final size = await File(picked.path).length();
      final ok = await NetworkGuard.confirmIfNotWifi(
        context,
        actionName: viewOnce ? '1回表示写真の送信' : '写真の送信',
        warnOnNonWifi: widget.store.warnOnNonWifi,
        fileSizeBytes: size,
      );
      if (!ok || !mounted) return;
 
      await widget.store.sendMessage(
        widget.groupId,
        text: viewOnce ? '👁 1回だけ表示の写真' : '🖼 写真',
        kind: 'photo',
        viewOncePhoto: viewOnce,
        expireHoursOverride: _expireOverride,
        silent: _silentMode,
        media: MediaAttachment(
          fileName: picked.name,
          localPath: picked.path,
          fileSizeBytes: size,
        ),
      );
    } catch (e, s) {
      ErrorGuard.record('写真選択エラー: $e', s);
    }
  }
 
  Future<void> _pickAndSendShortVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );
      if (picked == null || !mounted) return;
      final size = await File(picked.path).length();
      final ok = await NetworkGuard.confirmIfNotWifi(
        context,
        actionName: '軽量動画の送信',
        warnOnNonWifi: widget.store.warnOnNonWifi,
        fileSizeBytes: size,
      );
      if (!ok || !mounted) return;
 
      await widget.store.sendMessage(
        widget.groupId,
        text: '🎬 軽量動画メッセージ',
        kind: 'video',
        expireHoursOverride: _expireOverride,
        silent: _silentMode,
        media: MediaAttachment(
          fileName: picked.name,
          localPath: picked.path,
          fileSizeBytes: size,
        ),
      );
    } catch (e, s) {
      ErrorGuard.record('動画選択エラー: $e', s);
    }
  }
 
  Future<void> _pickAndSendAnyFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      if (res == null || res.files.isEmpty || !mounted) return;
      final f = res.files.single;
      if (f.path == null) return;
      final ok = await NetworkGuard.confirmIfNotWifi(
        context,
        actionName: 'ファイル送信（${f.name}）',
        warnOnNonWifi: widget.store.warnOnNonWifi,
        fileSizeBytes: f.size,
      );
      if (!ok || !mounted) return;
 
      await widget.store.sendMessage(
        widget.groupId,
        text: '📎 ${f.name}',
        kind: 'file',
        expireHoursOverride: _expireOverride,
        silent: _silentMode,
        media: MediaAttachment(
          fileName: f.name,
          localPath: f.path,
          fileSizeBytes: f.size,
        ),
      );
    } catch (e, s) {
      ErrorGuard.record('ファイル選択エラー: $e', s);
    }
  }
 
  Future<void> _openMediaFile(MediaAttachment media) async {
    if (media.localPath != null && File(media.localPath!).existsSync()) {
      await OpenFilex.open(media.localPath!);
    } else if (media.remoteUrl != null) {
      await ExternalAppLauncher.openUrl(context, media.remoteUrl!);
    }
  }
 
  Future<void> _openPhotoViewer(ChatMessage msg) async {
    final media = msg.media;
    if (media == null) return;
    if (msg.viewOncePhoto && msg.isViewedOnceBy(widget.store.myViewerKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この写真は閲覧済みのため再表示できません')),
      );
      return;
    }
 
    var renderedFrame = false;
 
    await showDialog<void>(
      context: context,
      builder: (BuildContext dc) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(msg.viewOncePhoto ? '1回だけ表示（閉じると消去）' : media.fileName),
          ),
          body: Center(
            child: media.localPath != null && File(media.localPath!).existsSync()
                ? InteractiveViewer(
                    child: Image.file(
                      File(media.localPath!),
                      frameBuilder: (BuildContext _, Widget child, int? frame, bool __) {
                        if (frame != null) renderedFrame = true;
                        return child;
                      },
                    ),
                  )
                : media.remoteUrl != null
                    ? InteractiveViewer(
                        child: Image.network(
                          media.remoteUrl!,
                          frameBuilder:
                              (BuildContext _, Widget child, int? frame, bool __) {
                            if (frame != null) renderedFrame = true;
                            return child;
                          },
                          loadingBuilder:
                              (BuildContext _, Widget child, ImageChunkEvent? p) {
                            if (p == null) return child;
                            return const CircularProgressIndicator();
                          },
                          errorBuilder: (_, __, ___) => const Text(
                            '通信エラーで画像を読み込めませんでした（回数は消費されません）',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    : const Text('画像データが見つかりません',
                        style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
 
    if (msg.viewOncePhoto && renderedFrame) {
      await widget.store.markViewOncePhotoViewed(widget.groupId, msg.id);
    }
  }
 
  Future<void> _openVideoViewer(MediaAttachment media) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _VideoPlayerDialog(media: media),
    );
  }
 
  Future<void> _openPollDialog() async {
    final qCtrl = TextEditingController();
    final o1 = TextEditingController(text: '賛成');
    final o2 = TextEditingController(text: '別日にしたい');
    final o3 = TextEditingController();
 
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext dc) => AlertDialog(
          title: const Text('簡易投票を作成'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(controller: qCtrl, decoration: const InputDecoration(labelText: '質問')),
                TextField(controller: o1, decoration: const InputDecoration(labelText: '選択肢 1')),
                TextField(controller: o2, decoration: const InputDecoration(labelText: '選択肢 2')),
                TextField(controller: o3, decoration: const InputDecoration(labelText: '選択肢 3（任意）')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dc).pop(false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.of(dc).pop(true), child: const Text('送信')),
          ],
        ),
      );
 
      if (ok == true && qCtrl.text.trim().isNotEmpty) {
        final opts = <String>[o1.text.trim(), o2.text.trim(), o3.text.trim()]
            .where((e) => e.isNotEmpty)
            .toList();
        if (opts.length >= 2) {
          await widget.store.sendMessage(
            widget.groupId,
            text: '📊 投票: ${qCtrl.text.trim()}',
            expireHoursOverride: _expireOverride,
            silent: _silentMode,
            poll: PollData(
              question: qCtrl.text.trim(),
              options: opts,
              votes: <String, List<String>>{},
            ),
          );
        }
      }
    } finally {
      qCtrl.dispose();
      o1.dispose();
      o2.dispose();
      o3.dispose();
    }
  }
 
  Future<void> _openSchedulePicker() async {
    if (_inputCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先に送信したい文章を入力してください')),
      );
      return;
    }
    final mins = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <int>[1, 5, 30, 60]
              .map(
                (int m) => ListTile(
                  leading: const Icon(Icons.schedule_send),
                  title: Text('$m分後に自動送信'),
                  onTap: () => Navigator.of(bc).pop(m),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (mins != null) await _sendNow(delay: Duration(minutes: mins));
  }
 
  void _openMentionPicker(ChatGroup group) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: group.members
              .map(
                (String name) => ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: Text('@$name'),
                  onTap: () {
                    Navigator.of(bc).pop();
                    _inputCtrl.text = '${_inputCtrl.text}@$name ';
                    _inputCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: _inputCtrl.text.length),
                    );
                    widget.store.updateDraft(group.id, _inputCtrl.text);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
 
  void _openTalkSettings(ChatGroup group) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bc) => StatefulBuilder(
        builder: (_, StateSetter setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${group.name} の通知・着信音設定',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SwitchListTile(
                  title: const Text('このトークの通知をミュート'),
                  value: group.muted,
                  onChanged: (bool v) {
                    setLocal(() => group.muted = v);
                    widget.store.updateTalkSettings(group, muted: v);
                  },
                ),
                const Text('カスタム着信音（5種）', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final tone in ringtoneOptions)
                  ListTile(
                    dense: true,
                    title: Text(tone),
                    trailing: group.ringtone == tone
                        ? const Icon(Icons.check_circle, color: Color(0xFF1B8A5A))
                        : null,
                    onTap: () {
                      setLocal(() => group.ringtone = tone);
                      widget.store.updateTalkSettings(group, ringtone: tone);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
 
  void _openMessageActions(ChatGroup group, ChatMessage msg) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bc) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: reactionEmojis
                    .map(
                      (String e) => InkWell(
                        onTap: () {
                          Navigator.of(bc).pop();
                          widget.store.toggleReaction(group.id, msg.id, e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('引用して返信'),
              onTap: () {
                Navigator.of(bc).pop();
                setState(() => _replyTarget = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin),
              title: Text(group.pinnedMessageId == msg.id ? 'ピン留め解除' : '画面上部にピン留め'),
              onTap: () {
                Navigator.of(bc).pop();
                widget.store.togglePin(
                  group,
                  group.pinnedMessageId == msg.id ? null : msg.id,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('別トークへ転送'),
              onTap: () {
                Navigator.of(bc).pop();
                _openForwardDialog(group, msg);
              },
            ),
            if (!msg.deletedForAll && msg.sender == widget.store.myName) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('メッセージを編集'),
                onTap: () {
                  Navigator.of(bc).pop();
                  _openEditDialog(group, msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('全員側から削除'),
                onTap: () {
                  Navigator.of(bc).pop();
                  widget.store.deleteMessageForAll(group.id, msg);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
 
  Future<void> _openEditDialog(ChatGroup group, ChatMessage msg) async {
    final ctrl = TextEditingController(text: msg.text);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext dc) => AlertDialog(
          title: const Text('メッセージを編集'),
          content: TextField(controller: ctrl, maxLines: 3),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dc).pop(false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.of(dc).pop(true), child: const Text('保存')),
          ],
        ),
      );
      if (ok == true && ctrl.text.trim().isNotEmpty) {
        widget.store.editMessage(group.id, msg, ctrl.text.trim());
      }
    } finally {
      ctrl.dispose();
    }
  }
 
  void _openForwardDialog(ChatGroup source, ChatMessage msg) {
    final others = widget.store.groups.where((g) => g.id != source.id).toList();
    if (others.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext dc) => SimpleDialog(
        title: const Text('転送先のトークを選択'),
        children: others
            .map(
              (ChatGroup target) => SimpleDialogOption(
                onPressed: () {
                  Navigator.of(dc).pop();
                  widget.store.sendMessage(
                    target.id,
                    text: msg.text,
                    kind: msg.kind,
                    media: msg.viewOncePhoto ? null : msg.media,
                    forwardedFrom: source.name,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('「${target.name}」へ転送しました')),
                  );
                },
                child: Text(target.name),
              ),
            )
            .toList(),
      ),
    );
  }
 
  String _remainingText(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'まもなく消去';
    if (diff.inHours >= 1) return '残り${diff.inHours}時間${diff.inMinutes % 60}分';
    return '残り${diff.inMinutes + 1}分';
  }
 
  Widget _buildMessageBody(ChatMessage m) {
    if (m.deletedForAll) {
      return Text(m.text, style: const TextStyle(fontStyle: FontStyle.italic));
    }
    if (m.kind == 'stamp') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(m.text, style: const TextStyle(fontSize: 24)),
      );
    }
    if (m.kind == 'voice' && m.media != null) {
      final playing = _playingMessageId == m.id;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: () => _playVoice(m),
            icon: Icon(playing ? Icons.stop_circle : Icons.play_circle),
          ),
          Flexible(child: Text(m.text)),
        ],
      );
    }
    if (m.kind == 'photo' && m.media != null) {
      if (m.viewOncePhoto) {
        final alreadyViewed = m.isViewedOnceBy(widget.store.myViewerKey);
        return OutlinedButton.icon(
          onPressed: alreadyViewed ? null : () => _openPhotoViewer(m),
          icon: Icon(alreadyViewed ? Icons.visibility_off : Icons.looks_one),
          label: Text(alreadyViewed ? '1回表示写真（閲覧済み・消去）' : '1回だけ表示の写真を開く'),
        );
      }
      return InkWell(
        onTap: () => _openPhotoViewer(m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (m.media!.localPath != null && File(m.media!.localPath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(m.media!.localPath!),
                  height: 150,
                  width: 220,
                  fit: BoxFit.cover,
                ),
              )
            else if (m.media!.remoteUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  m.media!.remoteUrl!,
                  height: 150,
                  width: 220,
                  fit: BoxFit.cover,
                ),
              )
            else
              Text(m.text),
          ],
        ),
      );
    }
    if (m.kind == 'video' && m.media != null) {
      return OutlinedButton.icon(
        onPressed: () => _openVideoViewer(m.media!),
        icon: const Icon(Icons.play_arrow),
        label: Text('軽量動画を再生 (${formatBytes(m.media!.fileSizeBytes)})'),
      );
    }
    if (m.kind == 'file' && m.media != null) {
      return OutlinedButton.icon(
        onPressed: () => _openMediaFile(m.media!),
        icon: const Icon(Icons.insert_drive_file),
        label: Text(
          '${m.media!.fileName} (${formatBytes(m.media!.fileSizeBytes)})',
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Text(m.text);
  }
 
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (BuildContext context, _) {
        final group = _group;
        if (group == null) {
          return const Scaffold(body: Center(child: Text('トークが見つかりません')));
        }
 
        final query = _searchCtrl.text.trim().toLowerCase();
        final visibleMessages = query.isEmpty
            ? group.messages
            : group.messages
                .where((m) =>
                    m.text.toLowerCase().contains(query) ||
                    m.sender.toLowerCase().contains(query) ||
                    (m.media?.fileName.toLowerCase().contains(query) ?? false))
                .toList();
 
        ChatMessage? pinned;
        if (group.pinnedMessageId != null) {
          for (final m in group.messages) {
            if (m.id == group.pinnedMessageId) {
              pinned = m;
              break;
            }
          }
        }
 
        final statusLine = _isTyping && widget.store.shareTypingStatus
            ? '入力中...'
            : widget.store.showOnlineStatus
                ? 'オンライン'
                : widget.store.showLastSeen
                    ? '最終接続: たった今'
                    : '${group.members.length}人';
 
        final activeExpire = _expireOverride ?? widget.store.defaultExpireHours;
 
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'トーク内を全文検索...',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(group.name, style: const TextStyle(fontSize: 16)),
                      Text(statusLine, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
            actions: <Widget>[
              IconButton(
                tooltip: '全文検索',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() {
                    _searching = !_searching;
                    if (!_searching) _searchCtrl.clear();
                  });
                },
              ),
              IconButton(
                tooltip: 'ミュート・カスタム着信音',
                icon: Icon(group.muted ? Icons.notifications_off : Icons.tune),
                onPressed: () => _openTalkSettings(group),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (widget.store.uploadProgress != null)
                Container(
                  color: const Color(0xFFE8F5E9),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '送信中: ${widget.store.uploadingFileName ?? "ファイル"} (${((widget.store.uploadProgress ?? 0) * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: widget.store.uploadProgress),
                    ],
                  ),
                ),
              if (pinned != null)
                Material(
                  color: const Color(0xFFFFF8E1),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.push_pin, size: 18),
                    title: Text(pinned.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => widget.store.togglePin(group, null),
                    ),
                  ),
                ),
              if (group.scheduledMessages.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: const Color(0xFFE3F2FD),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('予約送信待機中: ${group.scheduledMessages.length}件',
                      style: const TextStyle(fontSize: 12)),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visibleMessages.length,
                  itemBuilder: (_, int i) {
                    final m = visibleMessages[i];
                    final isMe = m.sender == widget.store.myName;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _openMessageActions(group, m),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            color: m.deletedForAll
                                ? const Color(0xFFEEEEEE)
                                : isMe
                                    ? const Color(0xFFDCF8C6)
                                    : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(m.sender,
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.bold)),
                                  if (m.silent)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(Icons.notifications_paused, size: 13),
                                    ),
                                  if (m.forwardedFrom != null)
                                    Text(' ・転送(${m.forwardedFrom})',
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.black54)),
                                ],
                              ),
                              if (m.replyPreview != null)
                                Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0x14000000),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(m.replyPreview!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              _buildMessageBody(m),
                              if (m.poll != null && !m.deletedForAll) ...<Widget>[
                                const SizedBox(height: 6),
                                for (var idx = 0; idx < m.poll!.options.length; idx++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                      ),
                                      onPressed: () =>
                                          widget.store.votePoll(group.id, m.id, idx),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: <Widget>[
                                          Expanded(child: Text(m.poll!.options[idx])),
                                          Text(
                                            '${(m.poll!.votes[idx.toString()] ?? const <String>[]).length}票',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                              if (m.reactions.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    children: m.reactions.entries
                                        .map(
                                          (e) => Chip(
                                            visualDensity: VisualDensity.compact,
                                            label: Text('${e.key} ${e.value.length}'),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                children: <Widget>[
                                  Text(
                                    '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black54),
                                  ),
                                  if (m.edited)
                                    const Text('(編集済)',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.black54)),
                                  Text('既読 ${m.readBy.length}',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.black54)),
                                  if (m.expiresAt != null)
                                    Text('⏱ ${_remainingText(m.expiresAt!)}',
                                        style: const TextStyle(
                                            fontSize: 10, color: Colors.deepOrange)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_replyTarget != null)
                Container(
                  color: const Color(0xFFECEFF1),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '返信先 (${_replyTarget!.sender}): ${_replyTarget!.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _replyTarget = null),
                      ),
                    ],
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: <Widget>[
                    ActionChip(
                      avatar: const Icon(Icons.timer, size: 16),
                      label: Text('消去: ${formatExpireLabel(activeExpire)}'),
                      onPressed: () {
                        final idx = expireChoices.indexOf(activeExpire);
                        setState(() => _expireOverride =
                            expireChoices[(idx + 1) % expireChoices.length]);
                      },
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: const Text('サイレント'),
                      selected: _silentMode,
                      onSelected: (bool v) => setState(() => _silentMode = v),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.emoji_emotions, size: 16),
                      label: const Text('スタンプ'),
                      onPressed: _openStampPicker,
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.alternate_email, size: 16),
                      label: const Text('メンション'),
                      onPressed: () => _openMentionPicker(group),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.poll, size: 16),
                      label: const Text('投票'),
                      onPressed: _openPollDialog,
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.schedule_send, size: 16),
                      label: const Text('予約'),
                      onPressed: _openSchedulePicker,
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 8, 8),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        tooltip: '写真・1回表示・軽量動画・無制限ファイル',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _openAttachmentSheet,
                      ),
                      IconButton(
                        tooltip: _recording ? '録音停止して送信' : 'ボイス録音開始',
                        icon: Icon(
                          _recording ? Icons.stop_circle : Icons.mic,
                          color: _recording ? Colors.red : null,
                        ),
                        onPressed: _toggleVoiceRecord,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _inputCtrl,
                          decoration: InputDecoration(
                            hintText: _recording ? '録音中...マイクボタンで送信' : 'メッセージを入力',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (String value) {
                            widget.store.updateDraft(group.id, value);
                            final nextTyping = value.trim().isNotEmpty;
                            if (nextTyping != _isTyping) {
                              setState(() => _isTyping = nextTyping);
                            }
                          },
                          onSubmitted: (_) => _sendNow(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: () => _sendNow(),
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
 
class _VideoPlayerDialog extends StatefulWidget {
  const _VideoPlayerDialog({required this.media});
  final MediaAttachment media;
 
  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}
 
class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  VideoPlayerController? _controller;
 
  @override
  void initState() {
    super.initState();
    _init();
  }
 
  Future<void> _init() async {
    try {
      if (widget.media.localPath != null &&
          File(widget.media.localPath!).existsSync()) {
        _controller = VideoPlayerController.file(File(widget.media.localPath!));
      } else if (widget.media.remoteUrl != null) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.media.remoteUrl!),
        );
      }
      await _controller?.initialize();
      await _controller?.play();
      if (mounted) setState(() {});
    } catch (e, s) {
      ErrorGuard.record('動画再生エラー: $e', s);
    }
  }
 
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return AlertDialog(
      title: Text(widget.media.fileName, overflow: TextOverflow.ellipsis),
      content: c != null && c.value.isInitialized
          ? AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))
          : const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
