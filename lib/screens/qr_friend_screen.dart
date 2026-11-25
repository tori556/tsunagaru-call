import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_models.dart';
import '../services/firebase_service.dart';

class QrFriendScreen extends StatefulWidget {
  const QrFriendScreen({super.key});

  @override
  State<QrFriendScreen> createState() => _QrFriendScreenState();
}

class _QrFriendScreenState extends State<QrFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _handledScan = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_handledScan) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null) return;

    final parsed = FirebaseService.instance.parseQrData(raw);
    if (parsed == null) return;

    _handledScan = true;
    await _showConfirmAddSheet(
      myId: parsed['myId'] ?? '',
      name: parsed['name'] ?? '',
      emoji: parsed['emoji'] ?? '😊',
    );
    _handledScan = false;
  }

  Future<void> _showConfirmAddSheet({
    required String myId,
    required String name,
    required String emoji,
  }) async {
    final nameCtrl = TextEditingController(text: name);
    final memoCtrl = TextEditingController();
    ContactCategory selectedCat = ContactCategory.family;

    await showModalBottomSheet(
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
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'QRコードを読み取りました！',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '相手のマイID: $myId',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '表示名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '関係カテゴリを選択',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: ContactCategory.values.map((c) {
                  return ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: selectedCat == c,
                    selectedColor: c.bgColor,
                    onSelected: (_) => setSheet(() => selectedCat = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: memoCtrl,
                decoration: const InputDecoration(
                  labelText: 'メモ（任意）',
                  hintText: '例：実家、〇〇課、同級生',
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
                      targetMyId: myId,
                      nickname: nameCtrl.text,
                      category: selectedCat,
                      emoji: emoji,
                      memo: memoCtrl.text,
                    );
                    if (!ctx.mounted) return;
                    if (err != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(err)));
                    } else {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${selectedCat.label}に友だち追加しました！'),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'この相手を友だち追加する',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb = FirebaseService.instance;
    final me = fb.currentUser;
    final qrData = fb.buildMyQrData();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F2),
      appBar: AppBar(
        title: const Text(
          'QRコードで友だち追加',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFFEA580C),
          indicatorColor: const Color(0xFFF97316),
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'マイQRコード'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR読み取り'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Tab 1: My QR Code
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: Color(0xFFF3E5D8)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${me?.emoji ?? '😊'} ${me?.displayName ?? '自分'}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'マイID: ${me?.myId ?? ''}',
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFFDBA74),
                            width: 2,
                          ),
                        ),
                        child: QrImageView(
                          data: qrData.isEmpty ? 'tsunagarucall://add' : qrData,
                          version: QrVersions.auto,
                          size: 210,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '家族や友達のスマホで「QR読み取り」を開いて\nこの画面を映すとすぐにつながります。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Share.share(
                            '「つながる電話」で友だちになろう！\n私のマイID：${me?.myId ?? ''}\n名前：${me?.displayName ?? ''}',
                          );
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('招待メッセージを送る'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Tab 2: Camera QR Scanner
          Stack(
            children: [
              MobileScanner(onDetect: _onQrDetected),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.all(18),
                  child: const Text(
                    '相手の「マイQRコード」を枠内に映してください',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
