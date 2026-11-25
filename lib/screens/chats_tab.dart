import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_models.dart';
import '../services/firebase_service.dart';
import 'chat_room_screen.dart';
import 'group_chat_screen.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  void _openCreateGroupDialog(BuildContext context) {
    final contacts = FirebaseService.instance.contacts;
    final nameCtrl = TextEditingController();
    ContactCategory chosenCat = ContactCategory.family;
    String chosenEmoji = '🏠';
    final selectedIds = <String>{};
    const groupEmojis = ['🏠', '💛', '💼', '🌸', '✨', '🎉', '⚽', '🍳'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '👥 新しいグループトークを作成',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'グループ名（必須）',
                    hintText: '例：家族連絡、同級生ランチ、企画チーム',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '関係カテゴリ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ContactCategory.values.map((c) {
                    return ChoiceChip(
                      label: Text('${c.emoji} ${c.label}'),
                      selected: chosenCat == c,
                      selectedColor: c.bgColor,
                      onSelected: (_) => setSheet(() => chosenCat = c),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                const Text(
                  'グループアイコン',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: groupEmojis.map((em) {
                    return ChoiceChip(
                      label: Text(em, style: const TextStyle(fontSize: 18)),
                      selected: chosenEmoji == em,
                      onSelected: (_) => setSheet(() => chosenEmoji = em),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  '招待するメンバーを選択（${selectedIds.length}人選択中）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (contacts.isEmpty)
                  const Text(
                    '先に「ホーム」から友だちを追加してください。',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...contacts.map((c) {
                    final checked = selectedIds.contains(c.id);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      title: Text('${c.emoji} ${c.name}（${c.category.label}）'),
                      onChanged: (v) {
                        setSheet(() {
                          if (v == true) {
                            selectedIds.add(c.id);
                          } else {
                            selectedIds.remove(c.id);
                          }
                        });
                      },
                    );
                  }),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('グループ名を入力してください')),
                        );
                        return;
                      }
                      final members = contacts
                          .where((c) => selectedIds.contains(c.id))
                          .toList();
                      final room = await FirebaseService.instance.createGroup(
                        name: nameCtrl.text,
                        emoji: chosenEmoji,
                        category: chosenCat,
                        members: members,
                      );
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      if (room != null) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => GroupChatScreen(group: room),
                        ));
                      }
                    },
                    child: const Text(
                      'グループを作成する',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb = FirebaseService.instance;
    final groups = List<GroupChatRoom>.from(fb.groups);
    final contacts = List<ContactItem>.from(fb.contacts);

    groups.sort((a, b) => (b.lastMessageAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.lastMessageAt?.millisecondsSinceEpoch ?? 0));
    contacts.sort((a, b) => (b.lastMessageAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.lastMessageAt?.millisecondsSinceEpoch ?? 0));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '👥 グループトーク',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7C2D12),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openCreateGroupDialog(context),
                icon: const Icon(Icons.group_add, size: 18),
                label: const Text('グループ作成'),
              ),
            ],
          ),
        ),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '家族や友達のグループを作成するとここに表示されます。',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          )
        else
          ...groups.map((g) {
            final cat = g.category;
            final timeStr = g.lastMessageAt != null
                ? DateFormat('HH:mm').format(g.lastMessageAt!)
                : '';
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: cat.bgColor,
                child: Text(g.emoji, style: const TextStyle(fontSize: 24)),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      '${g.name} (${g.memberUids.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (g.hasActiveCall)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        '📞通話中',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cat.bgColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: cat.fgColor,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                g.lastMessage ?? 'タップしてグループトークを開く',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  if (g.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${g.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupChatScreen(group: g),
                ));
              },
            );
          }),
        const Divider(height: 20),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Text(
            '💬 1対1トーク',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF7C2D12),
            ),
          ),
        ),
        if (contacts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '「ホーム」タブから友だちを追加すると\nここでトークできます 💬',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          )
        else
          ...contacts.map((c) {
            final cat = c.category;
            final timeStr = c.lastMessageAt != null
                ? DateFormat('HH:mm').format(c.lastMessageAt!)
                : '';
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: cat.bgColor,
                child: Text(c.emoji, style: const TextStyle(fontSize: 24)),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cat.bgColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      cat.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: cat.fgColor,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                c.lastMessage ?? 'タップしてトークを開始',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 4),
                  if (c.unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${c.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(contact: c),
                ));
              },
            );
          }),
      ],
    );
  }
}
