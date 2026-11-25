import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_models.dart';
import '../services/firebase_service.dart';
import 'active_call_screen.dart';
import 'chat_room_screen.dart';
import 'qr_friend_screen.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  String _selectedCat = 'all';

  void _openAddContactDialog() {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final memoCtrl = TextEditingController();
    ContactCategory chosenCat = _selectedCat == 'all'
        ? ContactCategory.family
        : ContactCategory.fromId(_selectedCat);
    String chosenEmoji = '😊';
    const emojis = ['👨', '👩', '🧒', '👧', '👵', '👴', '🧑', '👨‍💼', '👩‍💼', '😊', '🌸', '✨'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
                  '＋ マイIDで友だち追加',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: '相手のマイID（必須）',
                    hintText: '例：ln-ab12-cd34',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '表示名',
                    hintText: '例：お母さん、田中課長、けんた',
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
                      onSelected: (_) => setModalState(() => chosenCat = c),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text(
                  'アイコン',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: emojis.map((em) {
                    return ChoiceChip(
                      label: Text(em, style: const TextStyle(fontSize: 18)),
                      selected: chosenEmoji == em,
                      onSelected: (_) => setModalState(() => chosenEmoji = em),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: memoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'メモ（任意・役職や続柄など）',
                    hintText: '例：実家、〇〇課、高校の同級生',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () async {
                      final err = await FirebaseService.instance.addContactByMyId(
                        targetMyId: idCtrl.text,
                        nickname: nameCtrl.text,
                        category: chosenCat,
                        emoji: chosenEmoji,
                        memo: memoCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      if (err != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(err)));
                      } else {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${chosenCat.label}に追加しました')),
                        );
                      }
                    },
                    child: const Text(
                      '登録する',
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
    final me = fb.currentUser;
    final allContacts = fb.contacts;

    final filtered = _selectedCat == 'all'
        ? List<ContactItem>.from(allContacts)
        : allContacts.where((c) => c.category.id == _selectedCat).toList();

    filtered.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (me != null)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFF3E5D8)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFFFEDD5),
                    child: Text(me.emoji, style: const TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          me.displayName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'マイID: ${me.myId}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          me.statusMessage,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'QRコード',
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const QrFriendScreen(),
                      ));
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    tooltip: '共有',
                    icon: const Icon(Icons.share, size: 18),
                    onPressed: () {
                      Share.share(
                        '「つながる電話」で話そう！\n私のマイID：${me.myId}\n名前：${me.displayName}',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _CatFilterChip(
                label: '🌐 すべて (${allContacts.length})',
                selected: _selectedCat == 'all',
                onTap: () => setState(() => _selectedCat = 'all'),
              ),
              ...ContactCategory.values.map((c) {
                final cnt = allContacts.where((x) => x.category == c).length;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _CatFilterChip(
                    label: '${c.emoji} ${c.label} ($cnt)',
                    selected: _selectedCat == c.id,
                    onTap: () => setState(() => _selectedCat = c.id),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedCat == 'all'
                  ? '友だち・連絡先'
                  : '${ContactCategory.fromId(_selectedCat).emoji} ${ContactCategory.fromId(_selectedCat).label}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Color(0xFF7C2D12),
              ),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const QrFriendScreen(),
                    ));
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 17),
                  label: const Text('QR'),
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  onPressed: _openAddContactDialog,
                  icon: const Icon(Icons.person_add, size: 17),
                  label: const Text('ID追加'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'このカテゴリにはまだ連絡先がありません。\n右上の「QR」または「ID追加」から登録してください。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
          ),
        ...filtered.map((c) => _ContactCard(contact: c)),
      ],
    );
  }
}

class _CatFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CatFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : const Color(0xFF1F2937),
        ),
      ),
      selected: selected,
      selectedColor: const Color(0xFFF97316),
      backgroundColor: Colors.white,
      onSelected: (_) => onTap(),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ContactItem contact;

  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final cat = contact.category;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: contact.isOnline
              ? const Color(0xFF86EFAC)
              : const Color(0xFFF3E5D8),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: cat.bgColor,
                      child: Text(
                        contact.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: contact.isOnline
                              ? const Color(0xFF16A34A)
                              : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            contact.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cat.bgColor,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${cat.emoji} ${cat.label}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: cat.fgColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${contact.statusText}${contact.memo.isNotEmpty ? ' ・ ${contact.memo}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'お気に入り固定',
                  icon: Icon(
                    contact.pinned ? Icons.star : Icons.star_border,
                    color: contact.pinned ? Colors.amber[700] : Colors.grey,
                  ),
                  onPressed: () => FirebaseService.instance.togglePin(contact),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'delete') {
                      FirebaseService.instance.deleteContact(contact);
                    } else {
                      FirebaseService.instance.updateContactCategory(
                        contact,
                        ContactCategory.fromId(val),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    ...ContactCategory.values.map((c) => PopupMenuItem(
                          value: c.id,
                          child: Text('カテゴリ変更: ${c.emoji} ${c.label}'),
                        )),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '🗑️ 削除する',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(contact: contact),
                      ));
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('トーク'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ActiveCallScreen(
                          outgoingCallee: contact,
                          isVideo: false,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('音声'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ActiveCallScreen(
                          outgoingCallee: contact,
                          isVideo: true,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.videocam, size: 18),
                    label: const Text('ビデオ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
