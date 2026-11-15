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

/// Browser builds cannot read Wi-Fi; callers treat null as "unknown".
Future<NetworkFingerprint?> readNetworkFingerprint() async => null;
