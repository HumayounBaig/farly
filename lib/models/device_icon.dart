import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';
import 'farly_device.dart';

/// A saved glyph for a device: brand mark or emoji. Stored as a short id.
class DeviceIcon {
  const DeviceIcon._(this.id, {required this.label, this.emoji, this.brand});

  final String id;
  final String label;
  final String? emoji;
  final String? brand;

  bool get isEmoji => emoji != null;
  bool get isBrand => brand != null;

  static const brands = <DeviceIcon>[
    DeviceIcon._('brand:lg', label: 'LG', brand: 'LG'),
    DeviceIcon._('brand:samsung', label: 'Samsung', brand: 'SAMSUNG'),
    DeviceIcon._('brand:sony', label: 'Sony', brand: 'SONY'),
    DeviceIcon._('brand:roku', label: 'Roku', brand: 'ROKU'),
    DeviceIcon._('brand:tcl', label: 'TCL', brand: 'TCL'),
    DeviceIcon._('brand:hisense', label: 'Hisense', brand: 'HISENSE'),
    DeviceIcon._('brand:haier', label: 'Haier', brand: 'HAIER'),
    DeviceIcon._('brand:mi', label: 'Xiaomi', brand: 'MI'),
    DeviceIcon._('brand:philips', label: 'Philips', brand: 'PHILIPS'),
    DeviceIcon._('brand:google', label: 'Google TV', brand: 'GOOGLE'),
    DeviceIcon._('brand:apple', label: 'Apple TV', brand: 'APPLE'),
  ];

  static const emojis = <DeviceIcon>[
    DeviceIcon._('emoji:tv', label: 'TV', emoji: '📺'),
    DeviceIcon._('emoji:home', label: 'Home', emoji: '🏠'),
    DeviceIcon._('emoji:sofa', label: 'Lounge', emoji: '🛋️'),
    DeviceIcon._('emoji:bed', label: 'Bedroom', emoji: '🛏️'),
    DeviceIcon._('emoji:game', label: 'Games', emoji: '🎮'),
    DeviceIcon._('emoji:film', label: 'Movies', emoji: '🎬'),
    DeviceIcon._('emoji:popcorn', label: 'Popcorn', emoji: '🍿'),
    DeviceIcon._('emoji:star', label: 'Star', emoji: '⭐'),
    DeviceIcon._('emoji:fire', label: 'Fire', emoji: '🔥'),
    DeviceIcon._('emoji:moon', label: 'Night', emoji: '🌙'),
    DeviceIcon._('emoji:sun', label: 'Day', emoji: '☀️'),
    DeviceIcon._('emoji:music', label: 'Music', emoji: '🎵'),
    DeviceIcon._('emoji:plant', label: 'Plant', emoji: '🪴'),
    DeviceIcon._('emoji:box', label: 'Box', emoji: '📦'),
  ];

  static const all = [...brands, ...emojis];

  static DeviceIcon? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final icon in all) {
      if (icon.id == id) return icon;
    }
    return null;
  }

  /// Brand color for letter marks; warm horizon for everything else.
  Color get tint => switch (brand) {
    'LG' => const Color(0xFFA50034),
    'SAMSUNG' => const Color(0xFF1428A0),
    'SONY' => const Color(0xFF2A2A2A),
    'ROKU' => const Color(0xFF662D91),
    'TCL' => const Color(0xFFC8102E),
    'HISENSE' => const Color(0xFF00A19B),
    'HAIER' => const Color(0xFF0055A5),
    'MI' => const Color(0xFFE8590C),
    'PHILIPS' => const Color(0xFF0B5ED7),
    'GOOGLE' => const Color(0xFF4285F4),
    'APPLE' => const Color(0xFF555555),
    _ => FarlyColors.horizon,
  };

  /// Suggested icon when the user has not picked one yet.
  static String? suggestedId(FarlyDevice device) {
    if (device.kind == DeviceKind.climate) return null;
    return switch (device.brand) {
      DeviceBrand.lg => 'brand:lg',
      DeviceBrand.samsung => 'brand:samsung',
      DeviceBrand.sony => 'brand:sony',
      DeviceBrand.roku => 'brand:roku',
      DeviceBrand.appleTv => 'brand:apple',
      DeviceBrand.chromecast => 'brand:google',
      DeviceBrand.androidTv => _fromName(device.name) ?? 'emoji:tv',
      _ => _fromName(device.name),
    };
  }

  static String? _fromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('tcl')) return 'brand:tcl';
    if (lower.contains('hisense')) return 'brand:hisense';
    if (lower.contains('haier') ||
        lower.contains('matrix') ||
        RegExp(r'\baqua\b').hasMatch(lower)) {
      return 'brand:haier';
    }
    if (lower.contains('philips')) return 'brand:philips';
    if (lower.contains('xiaomi') || RegExp(r'\bmi\s?tv').hasMatch(lower)) {
      return 'brand:mi';
    }
    if (lower.contains('sony') || lower.contains('bravia')) return 'brand:sony';
    if (lower.contains('samsung')) return 'brand:samsung';
    if (lower.contains('lg')) return 'brand:lg';
    if (lower.contains('roku')) return 'brand:roku';
    return null;
  }
}
