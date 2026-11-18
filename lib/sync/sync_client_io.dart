import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:http/http.dart' as http;

import 'device_sync.dart';

class SyncPullException implements Exception {
  SyncPullException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Downloads the phone's device dump.
///
/// Prefer [endpoint] (`host:port` from the phone sheet). Bonjour is a fallback —
/// menu-bar apps often miss Local Network / mDNS discovery prompts.
Future<DeviceSyncPayload> pullDeviceSync({
  required String pin,
  String? endpoint,
  Duration timeout = const Duration(seconds: 10),
  http.Client? client,
}) async {
  final cleaned = pin.trim();
  if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) {
    throw SyncPullException('Enter the 6-digit code shown on the phone.');
  }

  final httpClient = client ?? http.Client();
  try {
    final manual = parseSyncEndpoint(endpoint ?? '');
    if (manual != null) {
      return await _fetch(
        httpClient,
        _SyncEndpoint(manual.host, manual.port),
        cleaned,
      );
    }

    final endpoints = await _discoverSyncEndpoints(timeout: timeout);
    if (endpoints.isEmpty) {
      throw SyncPullException(
        'No phone found on Wi‑Fi. Enter the address shown under the code on the phone (like 192.168.1.20:41234).',
      );
    }

    Object? lastError;
    for (final candidate in endpoints) {
      try {
        return await _fetch(httpClient, candidate, cleaned);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError is SyncPullException) throw lastError;
    throw SyncPullException(
      lastError?.toString() ?? 'Could not download devices from the phone.',
    );
  } finally {
    if (client == null) httpClient.close();
  }
}

Future<DeviceSyncPayload> _fetch(
  http.Client client,
  _SyncEndpoint endpoint,
  String pin,
) async {
  try {
    final probe = await Socket.connect(
      endpoint.host,
      endpoint.port,
      timeout: const Duration(seconds: 5),
    );
    probe.destroy();
  } on SocketException catch (error) {
    throw SyncPullException(
      'Could not reach ${endpoint.host}:${endpoint.port} (${error.message}). '
      'Same Wi‑Fi as the phone? On the Mac, enable Farly under '
      'System Settings → Privacy & Security → Local Network.',
    );
  } on TimeoutException {
    throw SyncPullException(
      'Timed out reaching ${endpoint.host}:${endpoint.port}. '
      'Same Wi‑Fi? Guest networks often block phone↔Mac traffic. '
      'Also enable Farly under System Settings → Privacy & Security → Local Network.',
    );
  }

  final uri = Uri(
    scheme: 'http',
    host: endpoint.host,
    port: endpoint.port,
    path: farlySyncPath,
  );
  try {
    final response = await client
        .get(uri, headers: {farlySyncPinHeader: pin})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == HttpStatus.unauthorized) {
      throw SyncPullException('That code did not match. Check the phone.');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw SyncPullException('Phone returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw SyncPullException('Phone sent an unexpected reply.');
    }
    return DeviceSyncPayload.fromJson(Map<String, dynamic>.from(decoded));
  } on TimeoutException {
    throw SyncPullException(
      'Connected, then timed out reading from ${endpoint.host}:${endpoint.port}. '
      'Keep Share with Mac open on the phone and try again.',
    );
  } on SocketException catch (error) {
    throw SyncPullException(
      'Lost the phone at ${endpoint.host}:${endpoint.port} (${error.message}).',
    );
  }
}

class _SyncEndpoint {
  const _SyncEndpoint(this.host, this.port);
  final String host;
  final int port;
}

Future<List<_SyncEndpoint>> _discoverSyncEndpoints({
  required Duration timeout,
}) async {
  final discovery = BonsoirDiscovery(type: farlySyncServiceType);
  final found = <String, _SyncEndpoint>{};
  final done = Completer<void>();
  Timer? settle;
  StreamSubscription<BonsoirDiscoveryEvent>? subscription;

  void finishSoon() {
    settle?.cancel();
    settle = Timer(const Duration(milliseconds: 800), () {
      if (!done.isCompleted) done.complete();
    });
  }

  try {
    await discovery.initialize();
    final events = discovery.eventStream;
    if (events == null) return const [];
    subscription = events.listen((event) async {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          try {
            await event.service.resolve(discovery.serviceResolver);
          } catch (_) {}
        case BonsoirDiscoveryServiceResolvedEvent():
          final service = event.service;
          final host = await _hostForService(service);
          if (host == null) return;
          found['$host:${service.port}'] = _SyncEndpoint(host, service.port);
          finishSoon();
        default:
          break;
      }
    });
    await discovery.start();
    await Future.any([
      done.future,
      Future<void>.delayed(timeout),
    ]);
  } catch (_) {
    return found.values.toList();
  } finally {
    settle?.cancel();
    await subscription?.cancel();
    try {
      await discovery.stop();
    } catch (_) {}
  }
  return found.values.toList();
}

Future<String?> _hostForService(BonsoirService service) async {
  final fromAddresses = _ipv4(service.hostAddresses);
  if (fromAddresses != null) return fromAddresses;

  final attributeIp = service.attributes['ip'];
  if (attributeIp != null) {
    final fromAttr = _ipv4([attributeIp]);
    if (fromAttr != null) return fromAttr;
  }

  final hostname = service.hostname?.replaceAll(RegExp(r'\.$'), '');
  if (hostname == null || hostname.isEmpty) return null;
  try {
    final lookedUp = await InternetAddress.lookup(hostname);
    return _ipv4([for (final address in lookedUp) address.address]);
  } catch (_) {
    return null;
  }
}

String? _ipv4(List<String> addresses) {
  for (final address in addresses) {
    final host = address.split('%').first;
    final parts = host.split('.');
    if (parts.length != 4) continue;
    if (parts.every((part) {
      final value = int.tryParse(part);
      return value != null && value >= 0 && value <= 255;
    })) {
      return host;
    }
  }
  return null;
}
