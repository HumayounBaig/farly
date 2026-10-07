import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/farly_device.dart';

abstract class DeviceStore {
  Future<List<FarlyDevice>> read();

  Future<void> write(List<FarlyDevice> devices);
}

class MemoryDeviceStore implements DeviceStore {
  MemoryDeviceStore([List<FarlyDevice>? seed]) : _devices = [...?seed];

  List<FarlyDevice> _devices;

  @override
  Future<List<FarlyDevice>> read() async => List.unmodifiable(_devices);

  @override
  Future<void> write(List<FarlyDevice> devices) async {
    _devices = [...devices];
  }
}

class PreferencesDeviceStore implements DeviceStore {
  static const _key = 'farly.devices';

  @override
  Future<List<FarlyDevice>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map) FarlyDevice.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<void> write(List<FarlyDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final device in devices) device.toJson()]);
    await preferences.setString(_key, encoded);
  }
}
