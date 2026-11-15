import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_layout.dart';

abstract class LayoutStore {
  Future<RemoteLayout> read();

  Future<void> write(RemoteLayout layout);
}

class MemoryLayoutStore implements LayoutStore {
  MemoryLayoutStore([RemoteLayout? seed]) : _layout = seed ?? RemoteLayout.defaults;

  RemoteLayout _layout;

  @override
  Future<RemoteLayout> read() async => _layout;

  @override
  Future<void> write(RemoteLayout layout) async {
    _layout = layout;
  }
}

class PreferencesLayoutStore implements LayoutStore {
  static const _key = 'farly.remoteLayout';

  @override
  Future<RemoteLayout> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return RemoteLayout.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return RemoteLayout.defaults;
      return RemoteLayout.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return RemoteLayout.defaults;
    }
  }

  @override
  Future<void> write(RemoteLayout layout) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(layout.toJson()));
  }
}
