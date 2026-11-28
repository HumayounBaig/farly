import '../models/farly_device.dart';
import '../state/device_merge.dart';

/// Bonjour type advertised while a phone is sharing its device list.
///
/// No hyphen in the type label — some Bonjour stacks are picky about that.
const farlySyncServiceType = '_farlysync._tcp';

const farlySyncPath = '/v1/export';
const farlySyncPinHeader = 'x-farly-pin';

/// Parses `192.168.1.20:41234` (port required).
({String host, int port})? parseSyncEndpoint(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final host = parts[0].trim();
  final port = int.tryParse(parts[1].trim());
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  final octets = host.split('.');
  if (octets.length != 4) return null;
  for (final octet in octets) {
    final number = int.tryParse(octet);
    if (number == null || number < 0 || number > 255) return null;
  }
  return (host: host, port: port);
}

/// Versioned dump of saved TVs + which one was last used.
class DeviceSyncPayload {
  const DeviceSyncPayload({
    required this.devices,
    this.lastConnectedId,
    this.lastConnectedByNetwork = const {},
    this.exportedAt,
    this.source = 'farly',
    this.version = 1,
  });

  final int version;
  final List<FarlyDevice> devices;
  final String? lastConnectedId;
  final Map<String, String> lastConnectedByNetwork;
  final DateTime? exportedAt;
  final String source;

  Map<String, dynamic> toJson() => {
    'version': version,
    'source': source,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'lastConnectedId': lastConnectedId,
    'lastConnectedByNetwork': lastConnectedByNetwork,
    'devices': [for (final device in devices) device.toJson()],
  };

  factory DeviceSyncPayload.fromJson(Map<String, dynamic> json) {
    final rawDevices = json['devices'];
    final rawNetworks = json['lastConnectedByNetwork'];
    return DeviceSyncPayload(
      version: json['version'] as int? ?? 1,
      source: json['source'] as String? ?? 'farly',
      exportedAt: json['exportedAt'] == null
          ? null
          : DateTime.tryParse(json['exportedAt'] as String),
      lastConnectedId: json['lastConnectedId'] as String?,
      lastConnectedByNetwork: rawNetworks is Map
          ? {
              for (final entry in rawNetworks.entries)
                if (entry.key is String &&
                    entry.value is String &&
                    (entry.key as String).isNotEmpty &&
                    (entry.value as String).isNotEmpty)
                  entry.key as String: entry.value as String,
            }
          : const {},
      devices: rawDevices is List
          ? [
              for (final item in rawDevices)
                if (item is Map)
                  FarlyDevice.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }
}

class SyncImportResult {
  const SyncImportResult({required this.added, required this.updated});

  final int added;
  final int updated;

  int get changed => added + updated;
}

/// Folds an imported dump into the local list.
///
/// Incoming pairing credentials win when present so the phone can unlock the
/// Mac companion without re-pairing every Samsung / LG / Roku.
List<FarlyDevice> mergeImportedDevices({
  required List<FarlyDevice> local,
  required List<FarlyDevice> imported,
}) {
  final merged = [...collapseDevices(local)];
  for (final incoming in imported) {
    final index = merged.indexWhere((saved) => sameDevice(saved, incoming));
    if (index < 0) {
      merged.add(incoming);
      continue;
    }
    merged[index] = combineImported(merged[index], incoming);
  }
  return collapseDevices(merged);
}

/// [incoming] is the shared copy. Keep local name locks and fill gaps from it.
FarlyDevice combineImported(FarlyDevice local, FarlyDevice incoming) {
  final host = incoming.host ?? local.host;
  return FarlyDevice(
    id: local.id.isNotEmpty ? local.id : incoming.id,
    name: local.nameLocked
        ? local.name
        : (incoming.hasGenericName ? local.name : incoming.name),
    kind: incoming.brand.rank <= local.brand.rank ? incoming.kind : local.kind,
    brand: incoming.brand.rank <= local.brand.rank ? incoming.brand : local.brand,
    host: host,
    port: incoming.port ?? local.port,
    token: incoming.token ?? local.token,
    clientKey: incoming.clientKey ?? local.clientKey,
    descriptionUrl: incoming.descriptionUrl ?? local.descriptionUrl,
    uid: incoming.uid ?? local.uid,
    source: incoming.source,
    lastSeen: _later(incoming.lastSeen, local.lastSeen),
    icon: local.icon ?? incoming.icon,
    nameLocked: local.nameLocked || incoming.nameLocked,
    hosts: mergeHostHistory(
      primary: host,
      newer: incoming.candidateHosts,
      older: local.candidateHosts,
    ),
    menuCommand: incoming.menuCommand ?? local.menuCommand,
    networkKeys: mergeNetworkKeys(
      newer: incoming.networkKeys,
      older: local.networkKeys,
    ),
    model: incoming.model ?? local.model,
  );
}

Map<String, String> mergeLastConnectedByNetwork({
  required Map<String, String> local,
  required Map<String, String> imported,
}) {
  return {...local, ...imported};
}

DateTime? _later(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}
