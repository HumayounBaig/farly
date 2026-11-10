import '../models/farly_device.dart';
import 'ssdp.dart';

FarlyDevice? classifySsdp(SsdpMessage message) {
  final location = parseLocation(message.location);
  final host = location?.host;
  if (host == null || host.isEmpty || host.contains(':')) return null;

  final blob =
      '${message.server ?? ''} ${message.searchTarget ?? ''} ${message.uniqueName ?? ''} ${message.location ?? ''}'
          .toLowerCase();
  final brand = _brandFromText(blob);
  if (brand == null) return null;

  final description = message.location;
  final keepDescription =
      description != null &&
      (description.contains('xml') || description.contains('desc'));

  return FarlyDevice(
    id: FarlyDevice.idFor(brand, host),
    name: brand.label,
    kind: brand.kind,
    brand: brand,
    host: host,
    port: brand.defaultPort,
    descriptionUrl: keepDescription ? description : null,
    uid: uidFromUsn(message.uniqueName),
    source: 'ssdp',
  );
}

/// The `uuid:` part of an SSDP USN, before any `::urn:` suffix.
String? uidFromUsn(String? usn) {
  if (usn == null) return null;
  final value = usn.trim();
  final start = value.toLowerCase().indexOf('uuid:');
  if (start < 0) return null;
  final rest = value.substring(start + 5);
  final end = rest.indexOf('::');
  return normalizeUid(end < 0 ? rest : rest.substring(0, end));
}

FarlyDevice? classifyService({
  required String type,
  required String name,
  required String? host,
  required int port,
  required Map<String, String> attributes,
}) {
  if (host == null || host.isEmpty || host.contains(':')) return null;
  final service = type.toLowerCase();
  final model = (attributes['model'] ?? attributes['am'] ?? '').toLowerCase();
  final label = name.trim();

  final DeviceBrand? brand;
  var displayName = label;
  var devicePort = port;
  String? uid;
  if (service.contains('androidtvremote')) {
    brand = DeviceBrand.androidTv;
  } else if (service.contains('googlecast')) {
    final castModel = (attributes['md'] ?? '').toLowerCase();
    brand = _castIsTv(castModel)
        ? DeviceBrand.androidTv
        : DeviceBrand.chromecast;
    final friendly = attributes['fn']?.trim() ?? '';
    displayName = friendly.isNotEmpty
        ? friendly
        : label.replaceFirst(RegExp(r'-[0-9a-fA-F]{32}$'), '');
    devicePort = DeviceBrand.androidTv.defaultPort!;
    uid = normalizeUid(
      attributes['id'] ??
          RegExp(r'-([0-9a-fA-F]{32})$').firstMatch(label)?.group(1),
    );
  } else if (service.contains('airplay') || service.contains('raop')) {
    final appleTv =
        model.contains('appletv') || label.toLowerCase().contains('apple tv');
    if (!appleTv) return null;
    brand = DeviceBrand.appleTv;
  } else {
    return null;
  }

  return FarlyDevice(
    id: FarlyDevice.idFor(brand, host),
    name: displayName.isEmpty ? brand.label : displayName,
    kind: brand.kind,
    brand: brand,
    host: host,
    port: brand == DeviceBrand.androidTv ? devicePort : brand.defaultPort,
    uid: uid,
    source: 'mdns',
  );
}

/// Cast model names that are Google TV or Android TV sets.
bool _castIsTv(String model) {
  if (model.isEmpty) return false;
  if (RegExp(r'\btv\b').hasMatch(model)) return true;
  return const [
    'tcl',
    'hisense',
    'bravia',
    'philips',
    'sharp',
    'toshiba',
    'xiaomi',
    'shield',
    'onn',
  ].any(model.contains);
}

/// A Cast device that also answers on the Android TV remote port.
FarlyDevice asAndroidTv(FarlyDevice cast) {
  final host = cast.host!;
  return FarlyDevice(
    id: FarlyDevice.idFor(DeviceBrand.androidTv, host),
    name: cast.name == cast.brand.label
        ? DeviceBrand.androidTv.label
        : cast.name,
    kind: DeviceKind.screen,
    brand: DeviceBrand.androidTv,
    host: host,
    port: DeviceBrand.androidTv.defaultPort,
    descriptionUrl: cast.descriptionUrl,
    uid: cast.uid,
    source: cast.source,
    icon: cast.icon,
    nameLocked: cast.nameLocked,
    hosts: cast.hosts,
  );
}

DeviceBrand? _brandFromText(String blob) {
  if (blob.contains('roku')) return DeviceBrand.roku;
  if (blob.contains('webos') ||
      blob.contains('lge') ||
      blob.contains('lg smart')) {
    return DeviceBrand.lg;
  }
  if (blob.contains('samsung') || blob.contains('tizen')) {
    return DeviceBrand.samsung;
  }
  if (blob.contains('bravia') || blob.contains('sony')) {
    return DeviceBrand.sony;
  }
  if (blob.contains('androidtv') || blob.contains('android tv')) {
    return DeviceBrand.androidTv;
  }
  if (blob.contains('google') || blob.contains('chromecast')) {
    return DeviceBrand.chromecast;
  }
  if (blob.contains('daikin') ||
      blob.contains('sensibo') ||
      blob.contains('tuya')) {
    return DeviceBrand.otherAc;
  }
  if (blob.contains('dial-multiscreen')) return DeviceBrand.unknown;
  return null;
}

/// One address can answer several protocols. Keep the best control path, plus
/// any name, identity, or description the other answers carried.
void putBetterDevice(Map<String, FarlyDevice> byHost, FarlyDevice device) {
  final host = device.host;
  if (host == null) return;
  final existing = byHost[host];
  if (existing == null) {
    byHost[host] = device;
    return;
  }
  final better = device.brand.rank < existing.brand.rank;
  final keep = better ? device : existing;
  final other = better ? existing : device;
  byHost[host] = keep.copyWith(
    name: keep.hasGenericName && !other.hasGenericName ? other.name : null,
    uid: keep.uid ?? other.uid,
    descriptionUrl: keep.descriptionUrl ?? other.descriptionUrl,
  );
}
