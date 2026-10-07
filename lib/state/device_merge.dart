import '../models/farly_device.dart';

List<FarlyDevice> mergeDevices({
  required List<FarlyDevice> saved,
  required List<FarlyDevice> found,
  required DateTime seenAt,
}) {
  final merged = <String, FarlyDevice>{
    for (final device in saved) device.id: device,
  };
  for (final device in found) {
    final previous = merged[device.id];
    merged[device.id] = FarlyDevice(
      id: device.id,
      name: previous == null ? device.name : _preferredName(previous, device),
      kind: device.kind,
      brand: device.brand,
      host: device.host,
      port: device.port ?? previous?.port,
      token: previous?.token ?? device.token,
      clientKey: previous?.clientKey ?? device.clientKey,
      descriptionUrl: device.descriptionUrl ?? previous?.descriptionUrl,
      source: device.source,
      lastSeen: seenAt,
    );
  }
  final devices = merged.values.toList();
  devices.sort((a, b) {
    final aSeen = a.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bSeen = b.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bSeen.compareTo(aSeen);
    if (byTime != 0) return byTime;
    return a.name.compareTo(b.name);
  });
  return devices;
}

String _preferredName(FarlyDevice saved, FarlyDevice found) {
  if (found.name != found.brand.label) return found.name;
  if (saved.name != saved.brand.label) return saved.name;
  return found.name;
}
