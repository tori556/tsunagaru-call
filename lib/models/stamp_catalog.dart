import 'package:flutter/material.dart';

class StampItem {
  final String id;
  final String packId;
  final String emoji;
  final String label;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;

  const StampItem({
    required this.id,
    required this.packId,
    required this.emoji,
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
  });
}

class StampPack {
  final String id;
  final String title;
  final String tabEmoji;
  final List<StampItem> stamps;

  const StampPack({
    required this.id,
    required this.title,
    required this.tabEmoji,
    required this.stamps,
  });
}

/// Phase 3: 4つのオリジナルスタンプパック（家族・仕事・友達・お祝い）
class StampCatalog {
  static const List<StampPack> packs = [
    StampPack(
      id: 'family',
      title: '家族・日常',
      tabEmoji: '🏠',
      stamps: [
        StampItem(
          id: 'fam_ok',
          packId: 'family',
          emoji: '🙆',
          label: '了解だよ！',
          bgColor: Color(0xFFFFF3E4),
          borderColor: Color(0xFFFDBA74),
          textColor: Color(0xFF9A3412),
        ),
        StampItem(
          id: 'fam_home',
          packId: 'family',
          emoji: '🚗',
          label: '今から帰るよ',
          bgColor: Color(0xFFDCFCE7),
          borderColor: Color(0xFF86EFAC),
          textColor: Color(0xFF166534),
        ),
        StampItem(
          id: 'fam_meal',
          packId: 'family',
          emoji: '🍚',
          label: 'ごはんできたよ',
          bgColor: Color(0xFFFEF3C7),
          borderColor: Color(0xFFFCD34D),
          textColor: Color(0xFF92400E),
        ),
        StampItem(
          id: 'fam_call',
          packId: 'family',
          emoji: '📞',
          label: '今電話できる？',
          bgColor: Color(0xFFDBEAFE),
          borderColor: Color(0xFF93C5FD),
          textColor: Color(0xFF1E40AF),
        ),
        StampItem(
          id: 'fam_thanks',
          packId: 'family',
          emoji: '💐',
          label: 'ありがとう！',
          bgColor: Color(0xFFFCE7F3),
          borderColor: Color(0xFFF9A8D4),
          textColor: Color(0xFF9D174D),
        ),
        StampItem(
          id: 'fam_night',
          packId: 'family',
          emoji: '🌙',
          label: 'おやすみ〜',
          bgColor: Color(0xFFEDE9FE),
          borderColor: Color(0xFFC4B5FD),
          textColor: Color(0xFF5B21B6),
        ),
      ],
    ),
    StampPack(
      id: 'work',
      title: '仕事・ていねい',
      tabEmoji: '💼',
      stamps: [
        StampItem(
          id: 'wrk_roger',
          packId: 'work',
          emoji: '🙇',
          label: '承知いたしました',
          bgColor: Color(0xFFDBEAFE),
          borderColor: Color(0xFF93C5FD),
          textColor: Color(0xFF1E3A8A),
        ),
        StampItem(
          id: 'wrk_thanks',
          packId: 'work',
          emoji: '✨',
          label: 'お疲れさまです',
          bgColor: Color(0xFFE0F2FE),
          borderColor: Color(0xFF7DD3FC),
          textColor: Color(0xFF075985),
        ),
        StampItem(
          id: 'wrk_check',
          packId: 'work',
          emoji: '📋',
          label: '確認いたします',
          bgColor: Color(0xFFF3F4F6),
          borderColor: Color(0xFFD1D5DB),
          textColor: Color(0xFF1F2937),
        ),
        StampItem(
          id: 'wrk_callback',
          packId: 'work',
          emoji: '📱',
          label: '後ほど折り返します',
          bgColor: Color(0xFFFEF3C7),
          borderColor: Color(0xFFFCD34D),
          textColor: Color(0xFF92400E),
        ),
        StampItem(
          id: 'wrk_done',
          packId: 'work',
          emoji: '✅',
          label: '完了しました！',
          bgColor: Color(0xFFDCFCE7),
          borderColor: Color(0xFF86EFAC),
          textColor: Color(0xFF166534),
        ),
        StampItem(
          id: 'wrk_help',
          packId: 'work',
          emoji: '🙏',
          label: 'よろしくお願いします',
          bgColor: Color(0xFFEDE9FE),
          borderColor: Color(0xFFC4B5FD),
          textColor: Color(0xFF5B21B6),
        ),
      ],
    ),
    StampPack(
      id: 'friends',
      title: '友達・リアクション',
      tabEmoji: '💛',
      stamps: [
        StampItem(
          id: 'frd_good',
          packId: 'friends',
          emoji: '👍',
          label: 'いいね！！',
          bgColor: Color(0xFFCCFBF1),
          borderColor: Color(0xFF5EEAD4),
          textColor: Color(0xFF115E59),
        ),
        StampItem(
          id: 'frd_lol',
          packId: 'friends',
          emoji: '😆',
          label: 'めっちゃ笑った',
          bgColor: Color(0xFFFEF9C3),
          borderColor: Color(0xFFFDE047),
          textColor: Color(0xFF854D0E),
        ),
        StampItem(
          id: 'frd_wait',
          packId: 'friends',
          emoji: '🏃',
          label: '今向かってる！',
          bgColor: Color(0xFFFFEDD5),
          borderColor: Color(0xFFFDBA74),
          textColor: Color(0xFF9A3412),
        ),
        StampItem(
          id: 'frd_sorry',
          packId: 'friends',
          emoji: '💦',
          label: 'ごめんね！',
          bgColor: Color(0xFFFEE2E2),
          borderColor: Color(0xFFFCA5A5),
          textColor: Color(0xFF991B1B),
        ),
        StampItem(
          id: 'frd_cheer',
          packId: 'friends',
          emoji: '🔥',
          label: 'ファイト！！',
          bgColor: Color(0xFFFFE4E6),
          borderColor: Color(0xFFFDA4AF),
          textColor: Color(0xFF9F1239),
        ),
        StampItem(
          id: 'frd_coffee',
          packId: 'friends',
          emoji: '☕',
          label: 'また話そうね',
          bgColor: Color(0xFFF3E8FF),
          borderColor: Color(0xFFD8B4FE),
          textColor: Color(0xFF6B21A8),
        ),
      ],
    ),
    StampPack(
      id: 'celebrate',
      title: 'お祝い・季節',
      tabEmoji: '🎉',
      stamps: [
        StampItem(
          id: 'cel_congrats',
          packId: 'celebrate',
          emoji: '🎉',
          label: 'おめでとう！！',
          bgColor: Color(0xFFFCE7F3),
          borderColor: Color(0xFFF9A8D4),
          textColor: Color(0xFF9D174D),
        ),
        StampItem(
          id: 'cel_bday',
          packId: 'celebrate',
          emoji: '🎂',
          label: 'お誕生日おめでとう',
          bgColor: Color(0xFFFFF3E4),
          borderColor: Color(0xFFFDBA74),
          textColor: Color(0xFF9A3412),
        ),
        StampItem(
          id: 'cel_sakura',
          packId: 'celebrate',
          emoji: '🌸',
          label: '応援してるよ！',
          bgColor: Color(0xFFFDF2F8),
          borderColor: Color(0xFFFBCFE8),
          textColor: Color(0xFFBE185D),
        ),
        StampItem(
          id: 'cel_care',
          packId: 'celebrate',
          emoji: '🍀',
          label: 'お大事にね',
          bgColor: Color(0xFFDCFCE7),
          borderColor: Color(0xFF86EFAC),
          textColor: Color(0xFF166534),
        ),
        StampItem(
          id: 'cel_morning',
          packId: 'celebrate',
          emoji: '☀️',
          label: 'おはよう！',
          bgColor: Color(0xFFFEF9C3),
          borderColor: Color(0xFFFDE047),
          textColor: Color(0xFF854D0E),
        ),
        StampItem(
          id: 'cel_gift',
          packId: 'celebrate',
          emoji: '🎁',
          label: 'いつも感謝です',
          bgColor: Color(0xFFEDE9FE),
          borderColor: Color(0xFFC4B5FD),
          textColor: Color(0xFF5B21B6),
        ),
      ],
    ),
  ];

  static StampItem? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in packs) {
      for (final s in p.stamps) {
        if (s.id == id) return s;
      }
    }
    return null;
  }
}
