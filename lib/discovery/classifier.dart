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
    source: 'ssdp',
  );
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
  if (service.contains('androidtvremote')) {
    brand = DeviceBrand.androidTv;
  } else if (service.contains('googlecast')) {
    brand = DeviceBrand.chromecast;
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
    name: label.isEmpty ? brand.label : label,
    kind: brand.kind,
    brand: brand,
    host: host,
    port: brand == DeviceBrand.androidTv ? port : brand.defaultPort,
    source: 'mdns',
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

void putBetterDevice(Map<String, FarlyDevice> byHost, FarlyDevice device) {
  final host = device.host;
  if (host == null) return;
  final existing = byHost[host];
  if (existing == null || device.brand.rank < existing.brand.rank) {
    byHost[host] = device;
  }
}
