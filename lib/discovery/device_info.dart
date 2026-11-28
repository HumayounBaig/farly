import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/farly_device.dart';
import 'ssdp.dart';

/// A friendly name and model a TV announced about itself. Both are cleaned.
typedef DeviceInfo = ({String? name, String? model});

DeviceInfo? _info(String? name, String? model) {
  final cleanName = cleanLabel(name);
  final cleanModel = cleanLabel(model);
  if (cleanName == null && cleanModel == null) return null;
  return (name: cleanName, model: cleanModel);
}

/// Roku `GET :8060/query/device-info`.
DeviceInfo? parseRokuInfo(String xml) => _info(
  xmlTag(xml, 'user-device-name') ?? xmlTag(xml, 'friendly-device-name'),
  xmlTag(xml, 'friendly-model-name') ?? xmlTag(xml, 'model-name'),
);

/// UPnP description XML (LG webOS and other DLNA TVs).
DeviceInfo? parseSsdpDescription(String xml) {
  final name = xmlTag(xml, 'modelName');
  final number = xmlTag(xml, 'modelNumber');
  // LG says "LG Smart TV" in modelName and keeps the real model in modelNumber.
  final useNumber =
      number != null && (name == null || !RegExp(r'\d').hasMatch(name));
  return _info(xmlTag(xml, 'friendlyName'), useNumber ? number : name);
}

/// Samsung Tizen `GET :8001/api/v2/`.
DeviceInfo? parseSamsungInfo(String body) {
  try {
    final json = jsonDecode(body);
    final device = json is Map ? json['device'] : null;
    if (device is! Map) return null;
    final name = device['name'];
    final model = device['modelName'];
    return _info(name is String ? name : null, model is String ? model : null);
  } catch (_) {
    return null;
  }
}

/// Cast mDNS TXT: `fn` is the friendly name and `md` the model.
DeviceInfo? parseCastTxt(Map<String, String> txt) =>
    _info(txt['fn'], txt['md']);

/// 10/8, 172.16/12 or 192.168/16, written as plain decimal octets: the only
/// hosts the scan may fetch from.
bool isPrivateIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final p = <int>[];
  for (final part in parts) {
    // No sign, hex or leading zeros: "010.0.0.1" is read differently by some stacks.
    if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) return false;
    final n = int.parse(part);
    if (n > 255) return false;
    p.add(n);
  }
  return p[0] == 10 ||
      (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
      (p[0] == 192 && p[1] == 168);
}

const _maxDescriptionBytes = 256 * 1024;

/// Asks the TV what it calls itself. Only private LAN IP literals the scan
/// already found are fetched, one short request each, with no redirects.
/// Samsung tries its own API first, then the SSDP description URL.
Future<DeviceInfo?> lookupDeviceInfo(
  http.Client client,
  FarlyDevice device,
) async {
  final host = device.host;
  if (host == null || !isPrivateIpv4(host)) return null;
  final tries = <(Uri, DeviceInfo? Function(String))>[];
  if (device.brand == DeviceBrand.roku) {
    tries.add((
      Uri.parse('http://$host:8060/query/device-info'),
      parseRokuInfo,
    ));
  } else if (device.brand == DeviceBrand.samsung) {
    tries.add((Uri.parse('http://$host:8001/api/v2/'), parseSamsungInfo));
  }
  if (device.brand != DeviceBrand.roku && device.descriptionUrl != null) {
    final parsed = Uri.tryParse(device.descriptionUrl!);
    // The description URL must point at the same address SSDP answered from.
    if (parsed != null && parsed.host == host) {
      tries.add((parsed, parseSsdpDescription));
    }
  }
  for (final (uri, parse) in tries) {
    try {
      final body = await _fetchBody(
        client,
        uri,
      ).timeout(const Duration(milliseconds: 1500));
      final info = body == null ? null : parse(body);
      if (info != null) return info;
    } catch (_) {
      // Try the next source.
    }
  }
  return null;
}

Future<String?> _fetchBody(http.Client client, Uri uri) async {
  final request = http.Request('GET', uri)
    ..followRedirects = false
    ..maxRedirects = 0;
  final response = await client.send(request);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    await response.stream.listen(null).cancel();
    return null;
  }
  final bytes = <int>[];
  await for (final chunk in response.stream) {
    bytes.addAll(chunk);
    if (bytes.length > _maxDescriptionBytes) return null;
  }
  return utf8.decode(bytes, allowMalformed: true);
}
