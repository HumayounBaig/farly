import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/farly_device.dart';

abstract class DeviceStore {
  Future<List<FarlyDevice>> read();

  Future<void> write(List<FarlyDevice> devices);

  /// The id of the device whose remote last connected.
  Future<String?> readLastConnected();

  Future<void> writeLastConnected(String? id);
}

class MemoryDeviceStore implements DeviceStore {
  MemoryDeviceStore([List<FarlyDevice>? seed, this._lastConnected])
    : _devices = [...?seed];

  List<FarlyDevice> _devices;
  String? _lastConnected;

  @override
  Future<List<FarlyDevice>> read() async => List.unmodifiable(_devices);

  @override
  Future<void> write(List<FarlyDevice> devices) async {
    _devices = [...devices];
  }

  @override
  Future<String?> readLastConnected() async => _lastConnected;

  @override
  Future<void> writeLastConnected(String? id) async {
    _lastConnected = id;
  }
}

class PreferencesDeviceStore implements DeviceStore {
  static const _key = 'farly.devices';
  static const _lastConnectedKey = 'farly.lastConnected';

  @override
  Future<List<FarlyDevice>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final devices = <FarlyDevice>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        devices.add(FarlyDevice.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // An entry from another app version: skip it, keep the rest.
      }
    }
    return devices;
  }

  @override
  Future<void> write(List<FarlyDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final device in devices) device.toJson()]);
    await preferences.setString(_key, encoded);
  }

  @override
  Future<String?> readLastConnected() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_lastConnectedKey);
  }

  @override
  Future<void> writeLastConnected(String? id) async {
    final preferences = await SharedPreferences.getInstance();
    if (id == null) {
      await preferences.remove(_lastConnectedKey);
    } else {
      await preferences.setString(_lastConnectedKey, id);
    }
  }
}
