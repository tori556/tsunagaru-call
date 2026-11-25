import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../models/stamp_catalog.dart';
import '../services/firebase_service.dart';
import '../widgets/chat_search_bar.dart';
import '../widgets/stamp_picker.dart';
import 'group_call_screen.dart';
import 'image_viewer_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupChatRoom group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _showStamps = false;
  bool _uploading = false;
  bool _searchMode = false;
  int _matchCursor = 0;

  @override
  void initState() {
    super.initState();
    FirebaseService.instance.markGroupRead(widget.group);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 140,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToMessageIndex(int msgIndex, int totalCount) {
    if (!_scroll.hasClients || totalCount <= 1) return;
    final ratio = (msgIndex / (totalCount - 1)).clamp(0.0, 1.0);
    _scroll.animateTo(
      _scroll.position.maxScrollExtent * ratio,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendText(String text) async {
    if (text.trim().isEmpty) return;
    await FirebaseService.instance.sendGroupMessage(
      group: widget.group,
      text: text,
    );
    _ctrl.clear();
    _scrollToBottom();
  }

  Future<void> _sendStamp(StampItem stamp) async {
    await FirebaseService.instance.sendStampToGroup(widget.group, stamp);
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (picked == null) return;
      setState(() => _uploading = true);
      await FirebaseService.instance.sendGroupMessage(
        group: widget.group,
        imageFile: File(picked.path),
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('写真の送信に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _openGroupCall(GroupChatRoom latestGroup, bool isVideo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupCallScreen(group: latestGroup, isVideo: isVideo),
    ));
  }

  void _showReadByMembers(GroupChatRoom latestGroup, ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '既読メンバー（${msg.readBy.length}人）',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...msg.readBy.map((uid) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.done_all, color: Color(0xFF16A34A)),
                    title: Text(latestGroup.memberNames[uid] ?? uid),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageBubble(ChatMessage m) {
    Widget thumb;
    if (m.imageUrl != null && m.imageUrl!.isNotEmpty) {
      thumb = Image.network(m.imageUrl!, width: 210, height: 210, fit: BoxFit.cover);
    } else {
      thumb = Image.file(File(m.localImagePath!), width: 210, height: 210, fit: BoxFit.cover);
    }
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ImageViewerScreen(
            imageUrl: m.imageUrl,
            localPath: m.localImagePath,
          ),
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: thumb,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb = FirebaseService.instance;
    final latestGroup = fb.findGroupById(widget.group.id) ?? widget.group;
    final myUid = fb.currentUser?.uid ?? 'demo_self';
    final cat = latestGroup.category;
    final query = _searchMode ? _searchCtrl.text.trim() : '';

    return Scaffold(
      backgroundColor: const Color(0xFFE9F2EC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            Text(latestGroup.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${latestGroup.name} (${latestGroup.memberUids.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cat.bgColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${cat.emoji} ${cat.label}グループ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: cat.fgColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'トーク内検索',
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _searchMode = !_searchMode;
                if (!_searchMode) {
                  _searchCtrl.clear();
                  _matchCursor = 0;
                }
              });
            },
          ),
          IconButton(
            tooltip: 'グループ音声通話',
            icon: const Icon(Icons.call, color: Color(0xFF16A34A)),
            onPressed: () => _openGroupCall(latestGroup, false),
          ),
          IconButton(
            tooltip: 'グループビデオ通話',
            icon: const Icon(Icons.videocam, color: Color(0xFF2563EB)),
            onPressed: () => _openGroupCall(latestGroup, true),
          ),
        ],
      ),
      body: StreamBuilder<List<ChatMessage>>(
        stream: fb.watchGroupMessages(latestGroup.id),
        builder: (context, snapshot) {
          final messages = snapshot.data ?? const [];

          final matches = <int>[];
          if (query.isNotEmpty) {
            final lq = query.toLowerCase();
            for (int i = 0; i < messages.length; i++) {
              if (messages[i].text.toLowerCase().contains(lq)) {
                matches.add(i);
              }
            }
          }
          if (_matchCursor >= matches.length) _matchCursor = 0;
          final focusedIdx = matches.isNotEmpty ? matches[_matchCursor] : -1;

          return Column(
            children: [
              // Active Group Call Join Banner (LINE-style)
              if (latestGroup.hasActiveCall)
                Container(
                  color: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.call, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'グループ通話中（${latestGroup.activeCall!.activeParticipantUids.length}人参加中）',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF15803D),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: () => _openGroupCall(
                          latestGroup,
                          latestGroup.activeCall!.isVideo,
                        ),
                        child: const Text(
                          '参加',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_searchMode)
                ChatSearchBar(
                  controller: _searchCtrl,
                  matchCount: matches.length,
                  currentMatchPos: _matchCursor,
                  onChanged: (_) => setState(() => _matchCursor = 0),
                  onPrev: () {
                    if (matches.isEmpty) return;
                    setState(() {
                      _matchCursor =
                          (_matchCursor - 1 + matches.length) % matches.length;
                    });
                    _jumpToMessageIndex(matches[_matchCursor], messages.length);
                  },
                  onNext: () {
                    if (matches.isEmpty) return;
                    setState(() {
                      _matchCursor = (_matchCursor + 1) % matches.length;
                    });
                    _jumpToMessageIndex(matches[_matchCursor], messages.length);
                  },
                  onClose: () {
                    setState(() {
                      _searchMode = false;
                      _searchCtrl.clear();
                      _matchCursor = 0;
                    });
                  },
                ),

              if (_uploading) const LinearProgressIndicator(minHeight: 3),

              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white70,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'グループトークをはじめましょう！\n右上のボタンからみんなでグループ通話もできます 📞',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF4B5563)),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(14),
                        itemCount: messages.length,
                        itemBuilder: (context, idx) {
                          final m = messages[idx];
                          final isMe = m.senderUid == myUid;
                          final timeStr = DateFormat('HH:mm').format(m.createdAt);
                          final rCount = m.readCount;
                          final isFocused = idx == focusedIdx;

                          return Container(
                            decoration: isFocused
                                ? BoxDecoration(
                                    color: const Color(0x33F97316),
                                    borderRadius: BorderRadius.circular(16),
                                  )
                                : null,
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 44,
                                      bottom: 2,
                                    ),
                                    child: Text(
                                      m.senderName.isEmpty
                                          ? 'メンバー'
                                          : m.senderName,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4B5563),
                                      ),
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!isMe) ...[
                                      CircleAvatar(
                                        radius: 17,
                                        backgroundColor: Colors.white,
                                        child: Text(m.senderEmoji),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (isMe)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 6),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (rCount > 0)
                                              GestureDetector(
                                                onTap: () => _showReadByMembers(
                                                  latestGroup,
                                                  m,
                                                ),
                                                child: Text(
                                                  '既読 $rCount',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF15803D),
                                                    fontWeight: FontWeight.bold,
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Flexible(
                                      child: m.hasImage
                                          ? _buildImageBubble(m)
                                          : (m.isStamp
                                              ? StampBubbleCard(
                                                  stampId: m.stampId,
                                                  fallbackText: m.text,
                                                )
                                              : Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isMe
                                                        ? const Color(
                                                            0xFF86EFAC)
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.only(
                                                      topLeft:
                                                          const Radius.circular(
                                                              18),
                                                      topRight:
                                                          const Radius.circular(
                                                              18),
                                                      bottomLeft:
                                                          Radius.circular(
                                                        isMe ? 18 : 4,
                                                      ),
                                                      bottomRight:
                                                          Radius.circular(
                                                        isMe ? 4 : 18,
                                                      ),
                                                    ),
                                                  ),
                                                  child: HighlightedMessageText(
                                                    text: m.text,
                                                    query: query,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Color(0xFF111827),
                                                    ),
                                                  ),
                                                )),
                                    ),
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Text(
                                          timeStr,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (_showStamps) StampPickerPanel(onStampSelected: _sendStamp),
              SafeArea(
                top: false,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '写真を送る',
                        icon: const Icon(
                          Icons.photo_camera_outlined,
                          color: Color(0xFF2563EB),
                        ),
                        onPressed: () =>
                            _pickAndSendImage(ImageSource.gallery),
                      ),
                      IconButton(
                        tooltip: 'スタンプパック',
                        icon: Icon(
                          _showStamps
                              ? Icons.keyboard
                              : Icons.emoji_emotions_outlined,
                          color: const Color(0xFFF97316),
                        ),
                        onPressed: () =>
                            setState(() => _showStamps = !_showStamps),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 4,
                          onTap: () {
                            if (_showStamps) setState(() => _showStamps = false);
                          },
                          decoration: InputDecoration(
                            hintText: 'グループへメッセージ',
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(12),
                        ),
                        onPressed: () => _sendText(_ctrl.text),
                        child: const Icon(Icons.send, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
