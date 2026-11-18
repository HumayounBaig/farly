import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'device_sync.dart';

/// Short-lived LAN share: HTTP JSON dump gated by a 6-digit PIN.
///
/// Bonjour is best-effort. The share sheet always shows `host:port` so the Mac
/// can connect when menu-bar Local Network / mDNS discovery fails.
class FarlySyncServer {
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  String _pin = '';
  String? _host;
  DeviceSyncPayload? _payload;
  Timer? _ttl;
  var _advertising = false;

  String get pin => _pin;
  int? get port => _server?.port;
  String? get host => _host;
  bool get isRunning => _server != null;
  bool get isAdvertising => _advertising;

  /// `192.168.1.20:41234` for the Mac import field.
  String? get endpointLabel {
    final host = _host;
    final port = _server?.port;
    if (host == null || port == null) return null;
    return '$host:$port';
  }

  Future<void> start(
    DeviceSyncPayload payload, {
    Duration ttl = const Duration(minutes: 2),
  }) async {
    await stop();
    _payload = payload;
    _pin = generateSyncPin();
    _host = await _wifiIpv4();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle);

    // Prove the listener accepts connections on this device.
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
        timeout: const Duration(seconds: 1),
      );
      probe.destroy();
    } catch (error) {
      await stop();
      throw StateError('Share server failed to listen ($error).');
    }

    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'Farly Sync',
          type: farlySyncServiceType,
          port: server.port,
          attributes: {
            'path': farlySyncPath,
            'ver': '1',
            if (_host != null) 'ip': _host!,
          },
        ),
      );
      _broadcast = broadcast;
      await broadcast.initialize();
      await broadcast.start();
      _advertising = true;
    } catch (error, stack) {
      _advertising = false;
      _broadcast = null;
      debugPrint('Farly sync Bonjour broadcast failed: $error\n$stack');
    }

    _ttl = Timer(ttl, () {
      unawaited(stop());
    });
  }

  Future<void> stop() async {
    _ttl?.cancel();
    _ttl = null;
    _payload = null;
    _advertising = false;
    _host = null;
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null) {
      try {
        await broadcast.stop();
      } catch (_) {}
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set(
      'Access-Control-Allow-Headers',
      farlySyncPinHeader,
    );
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final payload = _payload;
    if (payload == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    if (request.method != 'GET' || request.uri.path != farlySyncPath) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final offered =
        request.headers.value(farlySyncPinHeader) ??
        request.uri.queryParameters['pin'];
    if (offered != _pin) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('bad pin');
      await request.response.close();
      return;
    }

    final body = jsonEncode(payload.toJson());
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  }
}

String generateSyncPin() {
  final random = Random.secure();
  final value = random.nextInt(1000000);
  return value.toString().padLeft(6, '0');
}

/// Prefers the Wi‑Fi address; skips VPN / link-local / loopback.
Future<String?> _wifiIpv4() async {
  try {
    final wifi = await NetworkInfo().getWifiIP();
    final cleaned = wifi?.trim();
    if (cleaned != null && _isLanIpv4(cleaned)) return cleaned;
  } catch (_) {}

  try {
    final scored = <({String ip, int score})>[];
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    )) {
      final name = interface.name.toLowerCase();
      if (name.startsWith('utun') ||
          name.startsWith('ipsec') ||
          name.startsWith('ppp') ||
          name.startsWith('awdl') ||
          name.startsWith('llw')) {
        continue;
      }
      for (final address in interface.addresses) {
        if (address.isLoopback || !_isLanIpv4(address.address)) continue;
        var score = 1;
        if (name.startsWith('en')) score += 5;
        if (address.address.startsWith('192.168.')) score += 3;
        if (address.address.startsWith('10.')) score += 2;
        scored.add((ip: address.address, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isNotEmpty) return scored.first.ip;
  } catch (_) {}
  return null;
}

bool _isLanIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    octets.add(value);
  }
  // Skip link-local and loopback.
  if (octets[0] == 127) return false;
  if (octets[0] == 169 && octets[1] == 254) return false;
  // Private / CGNAT LAN ranges phones actually use on Wi‑Fi.
  if (octets[0] == 10) return true;
  if (octets[0] == 192 && octets[1] == 168) return true;
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
  if (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) return true;
  return false;
}
