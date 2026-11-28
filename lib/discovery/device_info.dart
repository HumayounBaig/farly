import 'dart:convert';

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

/// 10/8, 172.16/12, 192.168/16 or link-local: the only hosts the scan may fetch.
bool isPrivateIpv4(String host) {
  if (!isIpv4Address(host)) return false;
  final p = host.split('.').map(int.parse).toList();
  return p[0] == 10 ||
      (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
      (p[0] == 192 && p[1] == 168) ||
      (p[0] == 169 && p[1] == 254);
}
