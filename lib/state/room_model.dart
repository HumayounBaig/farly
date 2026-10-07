import 'package:flutter/foundation.dart';

import '../discovery/room_scan.dart';
import '../models/farly_device.dart';
import '../storage/device_store.dart';
import 'device_merge.dart';

class RoomModel extends ChangeNotifier {
  RoomModel({required this.store, Future<List<FarlyDevice>> Function()? scanDevices})
    : _scanDevices = scanDevices ?? scanRoom;

  final DeviceStore store;
  final Future<List<FarlyDevice>> Function() _scanDevices;

  List<FarlyDevice> devices = const [];
  DateTime? lastScanAt;
  bool scanning = false;
  String? notice;

  Future<void> load() async {
    try {
      devices = await store.read();
    } catch (_) {
      devices = const [];
    }
    notifyListeners();
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notice = null;
    notifyListeners();
    try {
      if (!roomScanSupported) {
        notice =
            'Scanning runs in the iOS and Android app. The browser cannot see your Wi-Fi.';
        return;
      }
      final found = await _scanDevices();
      final seenAt = DateTime.now();
      devices = mergeDevices(saved: devices, found: found, seenAt: seenAt);
      lastScanAt = seenAt;
      await store.write(devices);
      if (found.isEmpty) {
        notice =
            'Nothing answered. Use the same Wi-Fi as the TV, or add an address.';
      }
    } catch (_) {
      notice = 'The scan stopped early. You can add a device by address.';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> remember(FarlyDevice device) async {
    final seenAt = DateTime.now();
    devices = mergeDevices(
      saved: devices,
      found: [device],
      seenAt: seenAt,
    );
    await store.write(devices);
    notifyListeners();
  }

  Future<void> updateDevice(FarlyDevice device) async {
    devices = [
      for (final current in devices)
        if (current.id == device.id) device else current,
    ];
    await store.write(devices);
    notifyListeners();
  }

  Future<void> forget(FarlyDevice device) async {
    devices = [
      for (final current in devices)
        if (current.id != device.id) current,
    ];
    await store.write(devices);
    notifyListeners();
  }
}
