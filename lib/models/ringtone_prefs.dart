import 'dart:convert';
import 'app_models.dart';

/// カテゴリ別に選べる着信音プリセット
enum RingtonePreset {
  warmChime(
    'warm_chime',
    'やさしいチャイム',
    '家族におすすめのオルゴール風',
    'ringtones/ring_family.wav',
    'ring_family',
    'ring_family.wav',
  ),
  popBell(
    'pop_bell',
    '明るいベル',
    '友達からの着信にぴったり',
    'ringtones/ring_friends.wav',
    'ring_friends',
    'ring_friends.wav',
  ),
  businessTone(
    'business_tone',
    'ビジネス2トーン',
    '仕事関係向けの落ち着いた音',
    'ringtones/ring_work.wav',
    'ring_work',
    'ring_work.wav',
  ),
  gentleHarp(
    'gentle_harp',
    'やわらかいハープ',
    '親戚向けの上品な和音',
    'ringtones/ring_relatives.wav',
    'ring_relatives',
    'ring_relatives.wav',
  ),
  softTone(
    'soft_tone',
    '控えめソフトトーン',
    'その他・静かな場所向け',
    'ringtones/ring_other.wav',
    'ring_other',
    'ring_other.wav',
  ),
  systemDefault(
    'system_default',
    '端末の標準着信音',
    'スマホ本体の着信音を使用',
    '',
    'system_ringtone_default',
    'system_ringtone_default',
  );

  const RingtonePreset(
    this.id,
    this.label,
    this.description,
    this.assetPath,
    this.androidRawName,
    this.iosFileName,
  );

  final String id;
  final String label;
  final String description;
  final String assetPath;
  final String androidRawName;
  final String iosFileName;

  bool get hasPreviewAsset => assetPath.isNotEmpty;

  static RingtonePreset fromId(String? id) {
    return RingtonePreset.values.firstWhere(
      (e) => e.id == id,
      orElse: () => RingtonePreset.systemDefault,
    );
  }
}

class CategoryRingtoneSetting {
  final RingtonePreset preset;
  final bool vibrate;

  const CategoryRingtoneSetting({
    required this.preset,
    this.vibrate = true,
  });

  CategoryRingtoneSetting copyWith({
    RingtonePreset? preset,
    bool? vibrate,
  }) {
    return CategoryRingtoneSetting(
      preset: preset ?? this.preset,
      vibrate: vibrate ?? this.vibrate,
    );
  }

  Map<String, dynamic> toMap() => {
        'preset': preset.id,
        'vibrate': vibrate,
      };

  factory CategoryRingtoneSetting.fromMap(Map<String, dynamic> map) {
    return CategoryRingtoneSetting(
      preset: RingtonePreset.fromId(map['preset']?.toString()),
      vibrate: map['vibrate'] != false,
    );
  }
}

class RingtoneConfig {
  final Map<ContactCategory, CategoryRingtoneSetting> settings;

  const RingtoneConfig(this.settings);

  factory RingtoneConfig.defaults() {
    return const RingtoneConfig({
      ContactCategory.family: CategoryRingtoneSetting(
        preset: RingtonePreset.warmChime,
        vibrate: true,
      ),
      ContactCategory.friends: CategoryRingtoneSetting(
        preset: RingtonePreset.popBell,
        vibrate: true,
      ),
      ContactCategory.work: CategoryRingtoneSetting(
        preset: RingtonePreset.businessTone,
        vibrate: true,
      ),
      ContactCategory.relatives: CategoryRingtoneSetting(
        preset: RingtonePreset.gentleHarp,
        vibrate: true,
      ),
      ContactCategory.other: CategoryRingtoneSetting(
        preset: RingtonePreset.softTone,
        vibrate: false,
      ),
    });
  }

  CategoryRingtoneSetting forCategory(ContactCategory cat) {
    return settings[cat] ??
        const CategoryRingtoneSetting(preset: RingtonePreset.systemDefault);
  }

  RingtoneConfig withUpdated(
    ContactCategory cat,
    CategoryRingtoneSetting value,
  ) {
    final next = Map<ContactCategory, CategoryRingtoneSetting>.from(settings);
    next[cat] = value;
    return RingtoneConfig(next);
  }

  String toJsonString() {
    final map = <String, dynamic>{
      for (final e in settings.entries) e.key.id: e.value.toMap(),
    };
    return jsonEncode(map);
  }

  factory RingtoneConfig.fromJsonString(String? raw) {
    final base = RingtoneConfig.defaults();
    if (raw == null || raw.trim().isEmpty) return base;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final merged = Map<ContactCategory, CategoryRingtoneSetting>.from(
        base.settings,
      );
      for (final cat in ContactCategory.values) {
        final item = decoded[cat.id];
        if (item is Map) {
          merged[cat] = CategoryRingtoneSetting.fromMap(
            Map<String, dynamic>.from(item),
          );
        }
      }
      return RingtoneConfig(merged);
    } catch (_) {
      return base;
    }
  }
}
