import 'package:flutter/material.dart';
import '../models/stamp_catalog.dart';

/// LINE風のタブ切替オリジナルスタンプピッカー
class StampPickerPanel extends StatefulWidget {
  final void Function(StampItem stamp) onStampSelected;

  const StampPickerPanel({
    super.key,
    required this.onStampSelected,
  });

  @override
  State<StampPickerPanel> createState() => _StampPickerPanelState();
}

class _StampPickerPanelState extends State<StampPickerPanel> {
  int _packIdx = 0;

  @override
  Widget build(BuildContext context) {
    final pack = StampCatalog.packs[_packIdx];
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          // Pack Tab Bar
          Container(
            height: 44,
            color: const Color(0xFFFFF9F2),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              itemCount: StampCatalog.packs.length,
              itemBuilder: (context, idx) {
                final p = StampCatalog.packs[idx];
                final active = idx == _packIdx;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      '${p.tabEmoji} ${p.title}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : const Color(0xFF374151),
                      ),
                    ),
                    selected: active,
                    selectedColor: const Color(0xFFF97316),
                    backgroundColor: Colors.white,
                    onSelected: (_) => setState(() => _packIdx = idx),
                  ),
                );
              },
            ),
          ),

          // 3-Column Stamp Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.15,
              ),
              itemCount: pack.stamps.length,
              itemBuilder: (context, idx) {
                final st = pack.stamps[idx];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onStampSelected(st),
                  child: Container(
                    decoration: BoxDecoration(
                      color: st.bgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: st.borderColor, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(st.emoji, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 3),
                        Text(
                          st.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: st.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// トーク画面内で表示する大きなオリジナルスタンプカード
class StampBubbleCard extends StatelessWidget {
  final String? stampId;
  final String fallbackText;

  const StampBubbleCard({
    super.key,
    required this.stampId,
    required this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final item = StampCatalog.findById(stampId);
    if (item == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFDBA74), width: 2),
        ),
        child: Text(
          fallbackText,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF9A3412),
          ),
        ),
      );
    }

    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: item.bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: item.borderColor, width: 2.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              item.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: item.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
