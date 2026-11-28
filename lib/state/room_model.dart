import 'package:flutter/foundation.dart';

import '../discovery/network_context.dart';
import '../discovery/room_scan.dart';
import '../models/farly_device.dart';
import '../storage/device_store.dart';
import '../sync/device_sync.dart';
import 'device_merge.dart';

typedef NetworkReader = Future<NetworkFingerprint?> Function();

class RoomModel extends ChangeNotifier {
  RoomModel({
    required this.store,
    Future<List<FarlyDevice>> Function()? scanDevices,
    NetworkReader? readNetwork,
    this.retryDelay = const Duration(seconds: 2),
  }) : _scanDevices = scanDevices ?? scanRoom,
       _readNetwork = readNetwork ?? readNetworkFingerprint;

  final DeviceStore store;
  final Duration retryDelay;
  final Future<List<FarlyDevice>> Function() _scanDevices;
  final NetworkReader _readNetwork;

  List<FarlyDevice> devices = const [];
  DateTime? lastScanAt;
  bool scanning = false;
  String? notice;
  String? lastConnectedId;
  Map<String, String> lastConnectedByNetwork = const {};
  NetworkFingerprint? network;
  FarlyDevice? _autoOpen;
  var _scannedThisSession = false;

  FarlyDevice? get lastConnected {
    final id = lastConnectedId;
    if (id == null) return null;
    return _deviceForId(id);
  }

  /// Devices Farly believes belong on the current Wi-Fi.
  List<FarlyDevice> get devicesOnNetwork => [
    for (final device in devices)
      if (isOnCurrentNetwork(device)) device,
  ];

  /// Saved devices that belong to another network (or nowhere yet).
  List<FarlyDevice> get devicesElsewhere => [
    for (final device in devices)
      if (!isOnCurrentNetwork(device)) device,
  ];

  bool isOnCurrentNetwork(FarlyDevice device) {
    final current = network;
    if (current == null) return true;
    if (device.lastSeen != null && device.lastSeen == lastScanAt) return true;
    // Many routers share a default subnet (192.168.1.x), so a known Wi-Fi name
    // on both sides decides on its own.
    final ssids = device.networkKeys.where((k) => k.startsWith('ssid:'));
    if (current.ssidKey != null && ssids.isNotEmpty) {
      return ssids.contains(current.ssidKey);
    }
    if (current.matches(device.networkKeys)) return true;
    final hostSubnet = subnetKeyForHost(device.host);
    if (hostSubnet != null &&
        current.subnetKey != null &&
        hostSubnet == current.subnetKey) {
      return true;
    }
    return false;
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
    try {
      lastConnectedByNetwork = await store.readLastConnectedByNetwork();
    } catch (_) {
      lastConnectedByNetwork = const {};
    }
    await refreshNetwork(openLastRemote: true);
  }

  /// Re-reads Wi-Fi and optionally queues the last remote for this network.
  Future<void> refreshNetwork({bool openLastRemote = false}) async {
    try {
      network = await _readNetwork();
    } catch (_) {
      network = null;
    }
    if (openLastRemote) {
      _autoOpen = _remoteForCurrentNetwork();
    }
    notifyListeners();
  }

  FarlyDevice? _remoteForCurrentNetwork() {
    final key = network?.key;
    final id = key == null
        ? lastConnectedId
        : lastConnectedByNetwork[key] ?? lastConnectedId;
    if (id == null) return null;
    final device = _deviceForId(id);
    if (device == null) return null;
    if (device.kind != DeviceKind.screen || !device.brand.commandsReady) {
      return null;
    }
    if (network != null && !isOnCurrentNetwork(device)) return null;
    return device;
  }

  FarlyDevice? _deviceForId(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    final host = id.contains('@') ? id.split('@').last : null;
    if (host == null || host.isEmpty) return null;
    for (final device in devices) {
      if (device.host == host || device.hosts.contains(host)) return device;
    }
    return null;
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
        notice =
            'Scanning runs in the Farly app on iOS, Android, or Mac. The browser cannot see your Wi-Fi.';
        return;
      }
      await refreshNetwork();
      var found = await _scanDevices();
      if (found.isEmpty && !_scannedThisSession) {
        // On a fresh iOS install the Local Network prompt hides the first scan.
        await Future<void>.delayed(retryDelay);
        found = await _scanDevices();
      }
      _scannedThisSession = true;
      final seenAt = DateTime.now();
      final stamped = [
        for (final device in found) _stampNetwork(device),
      ];
      await _apply(mergeDevices(saved: devices, found: stamped, seenAt: seenAt));
      lastScanAt = seenAt;
      if (found.isEmpty) {
        notice =
            'Nothing answered. Allow Local Network for Farly, stay on the TV’s Wi-Fi, or Add by address.';
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
        found: [_stampNetwork(device)],
        seenAt: DateTime.now(),
        matchByName: false,
      ),
    );
    notifyListeners();
  }

  /// Snapshot for LAN share with the Mac companion.
  DeviceSyncPayload exportSyncPayload({String source = 'farly'}) {
    return DeviceSyncPayload(
      devices: devices,
      lastConnectedId: lastConnectedId,
      lastConnectedByNetwork: lastConnectedByNetwork,
      exportedAt: DateTime.now(),
      source: source,
    );
  }

  /// Merges a phone (or Mac) dump into the local saved list.
  Future<SyncImportResult> importSyncPayload(DeviceSyncPayload payload) async {
    final before = {for (final device in devices) device.id};
    final merged = mergeImportedDevices(
      local: devices,
      imported: payload.devices,
    );
    devices = merged;
    await store.write(devices);

    lastConnectedByNetwork = mergeLastConnectedByNetwork(
      local: lastConnectedByNetwork,
      imported: payload.lastConnectedByNetwork,
    );
    await store.writeLastConnectedByNetwork(lastConnectedByNetwork);

    final importedLast = payload.lastConnectedId;
    if (importedLast != null && _deviceForId(importedLast) != null) {
      lastConnectedId = importedLast;
      await store.writeLastConnected(importedLast);
      _autoOpen = _remoteForCurrentNetwork();
    }

    var added = 0;
    var updated = 0;
    for (final device in merged) {
      if (before.contains(device.id)) {
        if (payload.devices.any((item) => sameDevice(item, device))) {
          updated++;
        }
      } else if (payload.devices.any((item) => sameDevice(item, device))) {
        added++;
      }
    }
    notice = added + updated == 0
        ? 'Nothing new to import.'
        : 'Imported $added new, updated $updated.';
    notifyListeners();
    return SyncImportResult(added: added, updated: updated);
  }

  Future<void> updateDevice(FarlyDevice device) async {
    final index = devices.indexWhere(
      (current) => current.id == device.id || sameDevice(current, device),
    );
    if (index < 0) {
      devices = [...devices, _stampNetwork(device)];
    } else {
      final previous = devices[index];
      final merged = _stampNetwork(
        device.copyWith(
          hosts: mergeHostHistory(
            primary: device.host,
            newer: device.candidateHosts,
            older: previous.candidateHosts,
          ),
          networkKeys: mergeNetworkKeys(
            newer: device.networkKeys,
            older: previous.networkKeys,
          ),
        ),
      );
      devices = [
        for (var i = 0; i < devices.length; i++)
          if (i == index) merged else devices[i],
      ];
      if (lastConnectedId == previous.id && previous.id != merged.id) {
        await _rewriteLastConnectedIds(previous.id, merged.id);
      }
    }
    await store.write(devices);
    notifyListeners();
  }

  /// Scans once and returns the saved TV if it answered on a new address.
  Future<FarlyDevice?> relocate(FarlyDevice device) async {
    if (!roomScanSupported) return null;
    try {
      await refreshNetwork();
      final found = await _scanDevices();
      if (found.isEmpty) return null;
      final seenAt = DateTime.now();
      final stamped = [
        for (final item in found) _stampNetwork(item),
      ];
      await _apply(mergeDevices(saved: devices, found: stamped, seenAt: seenAt));
      lastScanAt = seenAt;
      notifyListeners();
      final match = findDevice(devices, device);
      if (match == null) return null;
      if (match.host == null) return null;
      if (match.host == device.host &&
          match.candidateHosts.every(device.candidateHosts.contains)) {
        return null;
      }
      return match;
    } catch (_) {
      return null;
    }
  }

  /// Remembers the device whose remote just connected, for this Wi-Fi.
  Future<void> markConnected(FarlyDevice device) async {
    if (device.brand == DeviceBrand.preview) return;
    if (network == null) {
      try {
        network = await _readNetwork();
      } catch (_) {
        network = null;
      }
    }
    final stamped = _stampNetwork(device);
    final networkKey = network?.key;
    final needsStamp = stamped.networkKeys.any(
      (item) => !device.networkKeys.contains(item),
    );
    final needsLast = lastConnectedId != stamped.id;
    final needsByNet =
        networkKey != null && lastConnectedByNetwork[networkKey] != stamped.id;
    if (!needsStamp && !needsLast && !needsByNet) return;

    if (needsStamp) {
      final index = devices.indexWhere(
        (current) => current.id == stamped.id || sameDevice(current, stamped),
      );
      if (index >= 0) {
        devices = [
          for (var i = 0; i < devices.length; i++)
            if (i == index) stamped else devices[i],
        ];
        await store.write(devices);
      }
    }
    if (needsLast) {
      lastConnectedId = stamped.id;
      await store.writeLastConnected(stamped.id);
    }
    if (networkKey != null && needsByNet) {
      final next = {...lastConnectedByNetwork, networkKey: stamped.id};
      lastConnectedByNetwork = next;
      await store.writeLastConnectedByNetwork(next);
    }
    notifyListeners();
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
    final pruned = {
      for (final entry in lastConnectedByNetwork.entries)
        if (entry.value != device.id) entry.key: entry.value,
    };
    if (pruned.length != lastConnectedByNetwork.length) {
      lastConnectedByNetwork = pruned;
      await store.writeLastConnectedByNetwork(pruned);
    }
    notifyListeners();
  }

  FarlyDevice _stampNetwork(FarlyDevice device) {
    final current = network;
    if (current == null) {
      final hostKey = subnetKeyForHost(device.host);
      if (hostKey == null) return device;
      return device.copyWith(
        networkKeys: mergeNetworkKeys(
          newer: [hostKey],
          older: device.networkKeys,
        ),
      );
    }
    return device.copyWith(
      networkKeys: mergeNetworkKeys(
        newer: current.stampKeys,
        older: device.networkKeys,
      ),
    );
  }

  Future<void> _rewriteLastConnectedIds(String from, String to) async {
    lastConnectedId = to;
    await store.writeLastConnected(to);
    final next = {
      for (final entry in lastConnectedByNetwork.entries)
        entry.key: entry.value == from ? to : entry.value,
    };
    lastConnectedByNetwork = next;
    await store.writeLastConnectedByNetwork(next);
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
      await _rewriteLastConnectedIds(previous.id, moved.id);
    }
  }
}
