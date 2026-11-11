import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stream_app.dart';

abstract class ShortcutStore {
  Future<List<ShortcutSlot>> read();

  Future<void> write(List<ShortcutSlot> slots);
}

class MemoryShortcutStore implements ShortcutStore {
  MemoryShortcutStore([List<ShortcutSlot>? seed])
    : _slots = [...(seed ?? ShortcutSlot.defaults)];

  List<ShortcutSlot> _slots;

  @override
  Future<List<ShortcutSlot>> read() async => List.unmodifiable(_slots);

  @override
  Future<void> write(List<ShortcutSlot> slots) async {
    _slots = _padded(slots);
  }
}

class PreferencesShortcutStore implements ShortcutStore {
  static const _key = 'farly.shortcuts';

  @override
  Future<List<ShortcutSlot>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return ShortcutSlot.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return ShortcutSlot.defaults;
      final slots = <ShortcutSlot>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        slots.add(ShortcutSlot.fromJson(Map<String, dynamic>.from(item)));
      }
      return _padded(slots);
    } catch (_) {
      return ShortcutSlot.defaults;
    }
  }

  @override
  Future<void> write(List<ShortcutSlot> slots) async {
    final preferences = await SharedPreferences.getInstance();
    final padded = _padded(slots);
    await preferences.setString(
      _key,
      jsonEncode([for (final slot in padded) slot.toJson()]),
    );
  }
}

List<ShortcutSlot> _padded(List<ShortcutSlot> slots) {
  final out = <ShortcutSlot>[];
  for (var i = 0; i < ShortcutSlot.count; i++) {
    out.add(
      i < slots.length ? slots[i] : ShortcutSlot.defaults[i],
    );
  }
  return out;
}
