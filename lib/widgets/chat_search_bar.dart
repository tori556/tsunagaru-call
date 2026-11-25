import 'package:flutter/material.dart';

/// LINE風のトーク内キーワード検索バー（該当件数＋上下ジャンプ）
class ChatSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final int matchCount;
  final int currentMatchPos;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const ChatSearchBar({
    super.key,
    required this.controller,
    required this.matchCount,
    required this.currentMatchPos,
    required this.onChanged,
    required this.onPrev,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'トーク内を検索…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (query.isNotEmpty)
            Text(
              matchCount == 0
                  ? '0件'
                  : '${currentMatchPos + 1}/$matchCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4B5563),
              ),
            ),
          IconButton(
            tooltip: '前の該当メッセージ',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: matchCount > 0 ? onPrev : null,
          ),
          IconButton(
            tooltip: '次の該当メッセージ',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: matchCount > 0 ? onNext : null,
          ),
          IconButton(
            tooltip: '検索を閉じる',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 検索キーワードを黄色マーカーでハイライト表示するテキストウィジェット
class HighlightedMessageText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;

  const HighlightedMessageText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return Text(text, style: style);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = cleanQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + cleanQuery.length),
        style: style.copyWith(
          backgroundColor: const Color(0xFFFDE047),
          fontWeight: FontWeight.w900,
        ),
      ));
      start = idx + cleanQuery.length;
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }
}
