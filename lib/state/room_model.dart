import 'package:flutter/foundation.dart';

import '../discovery/room_scan.dart';
import '../models/farly_device.dart';
import '../storage/device_store.dart';
import 'device_merge.dart';

class RoomModel extends ChangeNotifier {
  RoomModel({
    required this.store,
    Future<List<FarlyDevice>> Function()? scanDevices,
    this.retryDelay = const Duration(seconds: 2),
  }) : _scanDevices = scanDevices ?? scanRoom;

  final DeviceStore store;
  final Duration retryDelay;
  final Future<List<FarlyDevice>> Function() _scanDevices;

  List<FarlyDevice> devices = const [];
  DateTime? lastScanAt;
  bool scanning = false;
  String? notice;
  String? lastConnectedId;
  FarlyDevice? _autoOpen;
  var _scannedThisSession = false;

  FarlyDevice? get lastConnected {
    final id = lastConnectedId;
    if (id == null) return null;
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final saved = await store.read();
      devices = collapseDevices(saved);
      if (devices.length != saved.length) await store.write(devices);
    } catch (_) {
      devices = const [];
    }
    try {
      lastConnectedId = await store.readLastConnected();
    } catch (_) {
      lastConnectedId = null;
    }
    final last = lastConnected;
    if (last != null &&
        last.kind == DeviceKind.screen &&
        last.brand.commandsReady) {
      _autoOpen = last;
    }
    notifyListeners();
  }

  /// The remote to reopen at launch, handed out once.
  FarlyDevice? takeAutoOpen() {
    final device = _autoOpen;
    _autoOpen = null;
    return device;
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notice = null;
    notifyListeners();
    try {
      if (!roomScanSupported) {
        notice = 'Scanning runs in the iOS and Android app. The browser cannot see your Wi-Fi.';
        return;
      }
      var found = await _scanDevices();
      if (found.isEmpty && !_scannedThisSession) {
        // On a fresh iOS install the Local Network prompt hides the first scan.
        await Future<void>.delayed(retryDelay);
        found = await _scanDevices();
      }
      _scannedThisSession = true;
      final seenAt = DateTime.now();
      await _apply(mergeDevices(saved: devices, found: found, seenAt: seenAt));
      lastScanAt = seenAt;
      if (found.isEmpty) {
        notice = 'Nothing answered. On iPhone, allow Local Network access for Farly in Settings. Use the same Wi-Fi as the TV, or use Add by address (needed for LG, Samsung, Sony and Roku on iPhone).';
      }
    } catch (_) {
      notice = 'The scan stopped early. You can add a device by address.';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> remember(FarlyDevice device) async {
    await _apply(
      mergeDevices(
        saved: devices,
        found: [device],
        seenAt: DateTime.now(),
        matchByName: false,
      ),
    );
    notifyListeners();
  }

  Future<void> updateDevice(FarlyDevice device) async {
    final index = devices.indexWhere(
      (current) => current.id == device.id || sameDevice(current, device),
    );
    if (index < 0) {
      devices = [...devices, device];
    } else {
      final previous = devices[index];
      final merged = device.copyWith(
        hosts: mergeHostHistory(
          primary: device.host,
          newer: device.candidateHosts,
          older: previous.candidateHosts,
        ),
      );
      devices = [
        for (var i = 0; i < devices.length; i++)
          if (i == index) merged else devices[i],
      ];
      if (lastConnectedId == previous.id && previous.id != merged.id) {
        lastConnectedId = merged.id;
        await store.writeLastConnected(merged.id);
      }
    }
    await store.write(devices);
    notifyListeners();
  }

  /// Scans once and returns the saved TV if it answered on a new address.
  ///
  /// Used when the phone hops between 2.4 GHz / 5 GHz access points and the
  /// TV's DHCP lease moved.
  Future<FarlyDevice?> relocate(FarlyDevice device) async {
    if (!roomScanSupported) return null;
    try {
      final found = await _scanDevices();
      if (found.isEmpty) return null;
      final seenAt = DateTime.now();
      await _apply(mergeDevices(saved: devices, found: found, seenAt: seenAt));
      lastScanAt = seenAt;
      notifyListeners();
      final match = findDevice(devices, device);
      if (match == null) return null;
      if (match.host == null) return null;
      if (match.host == device.host &&
          match.candidateHosts.every(device.candidateHosts.contains)) {
        // Same address we already tried; nothing new to open.
        return null;
      }
      return match;
    } catch (_) {
      return null;
    }
  }

  /// Remembers the device whose remote just connected, for the next launch.
  Future<void> markConnected(FarlyDevice device) async {
    if (device.brand == DeviceBrand.preview) return;
    if (lastConnectedId == device.id) return;
    lastConnectedId = device.id;
    await store.writeLastConnected(device.id);
  }

  Future<void> forget(FarlyDevice device) async {
    devices = [
      for (final current in devices)
        if (current.id != device.id) current,
    ];
    await store.write(devices);
    if (lastConnectedId == device.id) {
      lastConnectedId = null;
      await store.writeLastConnected(null);
    }
    notifyListeners();
  }

  /// Saves a merged list, following the last connected device if the merge
  /// gave it a new id.
  Future<void> _apply(List<FarlyDevice> merged) async {
    final previous = lastConnected;
    devices = merged;
    await store.write(devices);
    if (previous == null) return;
    final moved = findDevice(devices, previous);
    if (moved != null && moved.id != previous.id) {
      lastConnectedId = moved.id;
      await store.writeLastConnected(moved.id);
    }
  }
}
