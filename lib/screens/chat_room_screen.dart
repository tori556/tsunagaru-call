import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../models/stamp_catalog.dart';
import '../services/firebase_service.dart';
import '../widgets/chat_search_bar.dart';
import '../widgets/stamp_picker.dart';
import 'active_call_screen.dart';
import 'image_viewer_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final ContactItem contact;

  const ChatRoomScreen({super.key, required this.contact});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
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
    FirebaseService.instance.markChatRead(widget.contact);
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

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    await FirebaseService.instance.sendMessage(
      target: widget.contact,
      text: text,
    );
    _ctrl.clear();
    _scrollToBottom();
  }

  Future<void> _sendStamp(StampItem stamp) async {
    await FirebaseService.instance.sendStampToContact(widget.contact, stamp);
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
      await FirebaseService.instance.sendImageMessage(
        target: widget.contact,
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

  void _showPhotoPickerSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFF97316)),
              title: const Text('アルバムから写真を選ぶ'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2563EB)),
              title: const Text('カメラで撮影して送る'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickAndSendImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startCall(bool isVideo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveCallScreen(
        outgoingCallee: widget.contact,
        isVideo: isVideo,
      ),
    ));
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
    final myUid = fb.currentUser?.uid ?? 'demo_self';
    final cat = widget.contact.category;
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
            Text(widget.contact.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contact.name,
                    style: const TextStyle(
                      fontSize: 16,
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
                      '${cat.emoji} ${cat.label}',
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
            tooltip: '音声通話',
            icon: const Icon(Icons.call, color: Color(0xFF16A34A)),
            onPressed: () => _startCall(false),
          ),
          IconButton(
            tooltip: 'ビデオ通話',
            icon: const Icon(Icons.videocam, color: Color(0xFF2563EB)),
            onPressed: () => _startCall(true),
          ),
        ],
      ),
      body: StreamBuilder<List<ChatMessage>>(
        stream: fb.watchMessages(widget.contact.targetUid),
        builder: (context, snapshot) {
          final messages = snapshot.data ?? const [];

          // Compute search matches
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
          final focusedMsgIdx =
              matches.isNotEmpty ? matches[_matchCursor] : -1;

          return Column(
            children: [
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
                            'メッセージ・写真・スタンプを送ったり、\n右上のボタンから電話をかけられます 📞',
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
                          final isFocused = idx == focusedMsgIdx;

                          return Container(
                            decoration: isFocused
                                ? BoxDecoration(
                                    color: const Color(0x33F97316),
                                    borderRadius: BorderRadius.circular(16),
                                  )
                                : null,
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: isMe
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!isMe) ...[
                                  CircleAvatar(
                                    radius: 17,
                                    backgroundColor: Colors.white,
                                    child: Text(widget.contact.emoji),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (m.isRead)
                                          const Text(
                                            '既読',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF15803D),
                                              fontWeight: FontWeight.bold,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? const Color(0xFF86EFAC)
                                                    : Colors.white,
                                                borderRadius: BorderRadius.only(
                                                  topLeft:
                                                      const Radius.circular(18),
                                                  topRight:
                                                      const Radius.circular(18),
                                                  bottomLeft: Radius.circular(
                                                    isMe ? 18 : 4,
                                                  ),
                                                  bottomRight: Radius.circular(
                                                    isMe ? 4 : 18,
                                                  ),
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x11000000),
                                                    blurRadius: 4,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: HighlightedMessageText(
                                                text: m.text,
                                                query: query,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
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
                        onPressed: _showPhotoPickerSheet,
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
                            hintText: 'メッセージを入力',
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
                        onPressed: () => _send(_ctrl.text),
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
