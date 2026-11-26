import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;

class SsdpMessage {
  const SsdpMessage(this.headers);

  final Map<String, String> headers;

  String? get location => headers['location'];
  String? get server => headers['server'];
  String? get searchTarget => headers['st'];
  String? get uniqueName => headers['usn'];
}

String msearch(String target) {
  return 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: $target\r\n'
      '\r\n';
}

SsdpMessage? parseSsdp(String raw) {
  final headers = <String, String>{};
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final split = line.indexOf(':');
    if (split <= 0) continue;
    headers[line.substring(0, split).trim().toLowerCase()] = line
        .substring(split + 1)
        .trim();
  }
  if (headers.isEmpty) return null;
  return SsdpMessage(headers);
}

Uri? parseLocation(String? location) {
  if (location == null || location.isEmpty) return null;
  final parsed = Uri.tryParse(location);
  if (parsed != null && parsed.host.isNotEmpty) return parsed;
  return Uri.tryParse('http://$location');
}

/// True when [host] is an IP literal equal to [sender] (zone suffix ignored).
bool locationMatchesSender(String? host, String sender) {
  final a = InternetAddress.tryParse(host?.split('%').first ?? '');
  final b = InternetAddress.tryParse(sender.split('%').first);
  return a != null && b != null && listEquals(a.rawAddress, b.rawAddress);
}

String? xmlTag(String body, String tag) {
  final match = RegExp(
    '<$tag>([^<]+)</$tag>',
    caseSensitive: false,
  ).firstMatch(body);
  final value = match?.group(1)?.trim();
  if (value == null || value.isEmpty) return null;
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
