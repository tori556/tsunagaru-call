import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/app_models.dart';
import '../services/firebase_service.dart';
import '../services/push_callkit_incoming.dart';
import 'group_call_screen.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});

  Future<void> _triggerDemoNativeCall(
    BuildContext context,
    ContactCategory cat,
    String name,
    String emoji,
    bool isVideo,
  ) async {
    final payload = IncomingCallPayload(
      callId: const Uuid().v4(),
      callerUid: 'demo_${cat.id}',
      callerName: '$name（デモ）',
      callerEmoji: emoji,
      category: cat,
      isVideo: isVideo,
      isDemo: true,
    );
    await PushCallKitService.showNativeIncomingCall(payload);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${cat.emoji} ${cat.label}からのネイティブ着信画面を起動しました'),
        ),
      );
    }
  }

  void _launchDemoGroupCall(BuildContext context, bool isVideo) {
    final groups = FirebaseService.instance.groups;
    final room = groups.isNotEmpty
        ? groups.first
        : GroupChatRoom(
            id: 'demo_grp',
            name: '家族連絡グループ',
            emoji: '🏠',
            category: ContactCategory.family,
            memberUids: ['demo_self', 'demo_grandma', 'demo_uncle'],
            memberNames: const {
              'demo_self': '自分',
              'demo_grandma': 'おばあちゃん',
              'demo_uncle': '岡山のおじさん',
            },
          );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupCallScreen(group: room, isVideo: isVideo),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final history = FirebaseService.instance.callHistory;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF93C5FD)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '👥 グループ音声・ビデオ通話テスト（LiveKit SFU）',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const Text(
                  '複数人グリッド表示・発話ハイライト・カメラ反転を今すぐ試せます。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                        ),
                        onPressed: () => _launchDemoGroupCall(context, false),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('グループ音声'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                        ),
                        onPressed: () => _launchDemoGroupCall(context, true),
                        icon: const Icon(Icons.videocam, size: 18),
                        label: const Text('グループビデオ'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFFDBA74)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔔 ネイティブ着信画面（CallKit / ロック画面）デモ',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('🏠 家族（ビデオ）'),
                      backgroundColor: ContactCategory.family.bgColor,
                      onPressed: () => _triggerDemoNativeCall(
                        context,
                        ContactCategory.family,
                        'おばあちゃん',
                        '👵',
                        true,
                      ),
                    ),
                    ActionChip(
                      label: const Text('💛 友達（音声）'),
                      backgroundColor: ContactCategory.friends.bgColor,
                      onPressed: () => _triggerDemoNativeCall(
                        context,
                        ContactCategory.friends,
                        'けんた',
                        '🧑',
                        false,
                      ),
                    ),
                    ActionChip(
                      label: const Text('💼 仕事関係（音声）'),
                      backgroundColor: ContactCategory.work.bgColor,
                      onPressed: () => _triggerDemoNativeCall(
                        context,
                        ContactCategory.work,
                        '佐藤課長',
                        '👨‍💼',
                        false,
                      ),
                    ),
                    ActionChip(
                      label: const Text('🌸 親戚（ビデオ）'),
                      backgroundColor: ContactCategory.relatives.bgColor,
                      onPressed: () => _triggerDemoNativeCall(
                        context,
                        ContactCategory.relatives,
                        '岡山のおじさん',
                        '👴',
                        true,
                      ),
                    ),
                    ActionChip(
                      label: const Text('✨ その他（音声）'),
                      backgroundColor: ContactCategory.other.bgColor,
                      onPressed: () => _triggerDemoNativeCall(
                        context,
                        ContactCategory.other,
                        '地域の連絡係',
                        '✨',
                        false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '📋 通話履歴',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF7C2D12),
          ),
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Card(
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'まだ通話履歴はありません。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
          )
        else
          ...history.map((h) {
            final cat = h.category;
            final timeStr = DateFormat('MM/dd HH:mm').format(h.createdAt);
            final dir = h.isMissed
                ? '不在着信'
                : (h.isOutgoing ? '発信' : '着信');
            return Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cat.bgColor,
                  child: Text(h.peerEmoji),
                ),
                title: Text(
                  '${h.peerName}（${cat.label}）',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: h.isMissed ? Colors.red : const Color(0xFF1F2937),
                  ),
                ),
                subtitle: Text(
                  '$dir・${h.isVideo ? 'ビデオ' : '音声'}・${h.durationSec}秒',
                ),
                trailing: Text(
                  timeStr,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            );
          }),
      ],
    );
  }
}
