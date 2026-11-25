import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_models.dart';
import '../models/ringtone_prefs.dart';
import '../services/firebase_service.dart';
import '../services/push_callkit_incoming.dart';

/// Phase 4: 5カテゴリ別の着信音カスタマイズ・試聴・着信テスト画面
class RingtoneSettingsScreen extends StatefulWidget {
  const RingtoneSettingsScreen({super.key});

  @override
  State<RingtoneSettingsScreen> createState() => _RingtoneSettingsScreenState();
}

class _RingtoneSettingsScreenState extends State<RingtoneSettingsScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingKey;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingKey = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _previewPreset(String key, RingtonePreset preset) async {
    if (_playingKey == key) {
      await _player.stop();
      setState(() => _playingKey = null);
      return;
    }
    if (!preset.hasPreviewAsset) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端末の標準着信音が鳴ります（下の「着信テスト」で確認可能）')),
      );
      return;
    }
    try {
      await _player.stop();
      setState(() => _playingKey = key);
      await _player.play(AssetSource(preset.assetPath));
    } catch (e) {
      if (mounted) {
        setState(() => _playingKey = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('試聴再生エラー: $e')),
        );
      }
    }
  }

  Future<void> _testCategoryCallKit(ContactCategory cat) async {
    await _player.stop();
    setState(() => _playingKey = null);
    final payload = IncomingCallPayload(
      callId: const Uuid().v4(),
      callerUid: 'test_${cat.id}',
      callerName: '${cat.label}テスト着信',
      callerEmoji: cat.emoji,
      category: cat,
      isVideo: false,
      isDemo: true,
    );
    await PushCallKitService.showNativeIncomingCall(payload);
  }

  void _openPresetPicker(ContactCategory cat, CategoryRingtoneSetting current) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${cat.emoji} ${cat.label}の着信音をえらぶ',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...RingtonePreset.values.map((preset) {
                final selected = current.preset == preset;
                final key = '${cat.id}_${preset.id}';
                return ListTile(
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? const Color(0xFFF97316) : Colors.grey,
                  ),
                  title: Text(
                    preset.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    preset.description,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: preset.hasPreviewAsset
                      ? IconButton(
                          tooltip: '試聴',
                          icon: Icon(
                            _playingKey == key
                                ? Icons.stop_circle
                                : Icons.play_circle_outline,
                            color: const Color(0xFFEA580C),
                          ),
                          onPressed: () => _previewPreset(key, preset),
                        )
                      : null,
                  onTap: () async {
                    await FirebaseService.instance.updateCategoryRingtone(
                      cat,
                      current.copyWith(preset: preset),
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    setState(() {});
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = FirebaseService.instance.ringtoneConfig;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F2),
      appBar: AppBar(
        title: const Text(
          'カテゴリ別の着信音設定',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            elevation: 0,
            color: Color(0xFFFFF3E4),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '家族・友達・仕事関係・親戚・その他ごとに異なる着信音を設定できます。着信音が鳴っただけで誰からの電話かすぐ分かります 🔔',
                style: TextStyle(fontSize: 13, color: Color(0xFF7C2D12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...ContactCategory.values.map((cat) {
            final setting = config.forCategory(cat);
            final key = 'card_${cat.id}';
            return Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFF3E5D8)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: cat.bgColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${cat.emoji} ${cat.label}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cat.fgColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            setting.preset.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '試聴',
                          icon: Icon(
                            _playingKey == key
                                ? Icons.stop_circle
                                : Icons.volume_up_outlined,
                            color: const Color(0xFFF97316),
                          ),
                          onPressed: () => _previewPreset(key, setting.preset),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openPresetPicker(cat, setting),
                            icon: const Icon(Icons.music_note, size: 17),
                            label: const Text('着信音を変更'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _testCategoryCallKit(cat),
                            icon: const Icon(Icons.ring_volume, size: 17),
                            label: const Text('着信テスト'),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'バイブレーション',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: setting.vibrate,
                      onChanged: (v) async {
                        await FirebaseService.instance.updateCategoryRingtone(
                          cat,
                          setting.copyWith(vibrate: v),
                        );
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
