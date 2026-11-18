import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// The phone's current Wi-Fi fingerprint when Farly can tell it apart.
class NetworkFingerprint {
  const NetworkFingerprint({
    required this.key,
    required this.label,
    this.ssidKey,
    this.subnetKey,
  });

  /// Preferred id for maps: SSID when known, otherwise the /24 subnet.
  final String key;

  /// Short label for the UI ("HomeWiFi" or "192.168.1.x").
  final String label;

  final String? ssidKey;
  final String? subnetKey;

  /// Keys to stamp onto a device seen on this network.
  List<String> get stampKeys => [
    ?ssidKey,
    ?subnetKey,
  ];

  bool matches(List<String> deviceKeys) {
    if (deviceKeys.isEmpty) return false;
    if (deviceKeys.contains(key)) return true;
    if (ssidKey != null && deviceKeys.contains(ssidKey)) return true;
    if (subnetKey != null && deviceKeys.contains(subnetKey)) return true;
    return false;
  }
}

String? subnetKeyForHost(String? host) {
  if (host == null) return null;
  final parts = host.trim().split('.');
  if (parts.length != 4) return null;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return null;
  }
  return 'subnet:${parts[0]}.${parts[1]}.${parts[2]}';
}

String ssidKeyFor(String ssid) => 'ssid:${ssid.trim()}';

/// Reads SSID when location is allowed, otherwise the phone's /24 subnet.
Future<NetworkFingerprint?> readNetworkFingerprint() async {
  final subnet = await _localSubnetKey();
  final ssid = await _wifiName();
  if (ssid != null && ssid.isNotEmpty) {
    final key = ssidKeyFor(ssid);
    return NetworkFingerprint(
      key: key,
      label: ssid,
      ssidKey: key,
      subnetKey: subnet,
    );
  }
  if (subnet == null) return null;
  final parts = subnet.substring('subnet:'.length);
  return NetworkFingerprint(
    key: subnet,
    label: '$parts.x',
    subnetKey: subnet,
  );
}

Future<String?> _wifiName() async {
  try {
    // permission_handler has no macOS implementation; SSID may still work.
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.locationWhenInUse.status;
      if (!status.isGranted) {
        final asked = await Permission.locationWhenInUse.request();
        if (!asked.isGranted) return null;
      }
    }
    final raw = await NetworkInfo().getWifiName();
    if (raw == null) return null;
    final cleaned = raw.replaceAll('"', '').trim();
    return cleaned.isEmpty ? null : cleaned;
  } catch (_) {
    return null;
  }
}

Future<String?> _localSubnetKey() async {
  try {
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final address in interface.addresses) {
        if (address.isLoopback) continue;
        final key = subnetKeyForHost(address.address);
        if (key != null) return key;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}
