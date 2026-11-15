import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:http/http.dart' as http;

import '../models/farly_device.dart';
import 'broadlink_hello.dart';
import 'classifier.dart';
import 'ssdp.dart';

const bool roomScanSupported = true;

const _serviceTypes = [
  '_googlecast._tcp',
  '_androidtvremote2._tcp',
  '_airplay._tcp',
  '_raop._tcp',
];

const _searchTargets = [
  'ssdp:all',
  'roku:ecp',
  'urn:dial-multiscreen-org:service:dial:1',
  'urn:lge-com:service:webos-second-screen:1',
  'urn:schemas-upnp-org:device:MediaRenderer:1',
];

Future<List<FarlyDevice>> scanRoom() async {
  final byHost = <String, FarlyDevice>{};
  await Future.wait([
    _ssdp(byHost),
    _broadlink(byHost),
    for (final type in _serviceTypes) _browse(type, byHost),
  ]);
  await _promoteCastTvs(byHost);
  await _enrichNames(byHost);
  return byHost.values.toList();
}

/// Google TV sets often announce only Cast. If one also answers on the
/// Android TV remote ports, it can take remote buttons.
Future<void> _promoteCastTvs(Map<String, FarlyDevice> byHost) async {
  final casts = byHost.entries
      .where((entry) => entry.value.brand == DeviceBrand.chromecast)
      .toList();
  await Future.wait(
    casts.map((entry) async {
      if (await _answersAtvRemote(entry.key)) {
        byHost[entry.key] = asAndroidTv(entry.value);
      }
    }),
  );
}

Future<bool> _answersAtvRemote(String host) async {
  for (final port in [
    DeviceBrand.androidTv.defaultPort!,
    6467,
  ]) {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.destroy();
      return true;
    } catch (_) {
      // Try the other port.
    }
  }
  return false;
}

Future<void> _ssdp(Map<String, FarlyDevice> byHost) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    void search() {
      for (final target in _searchTargets) {
        socket?.send(
          utf8.encode(msearch(target)),
          InternetAddress('239.255.255.250'),
          1900,
        );
      }
    }

    search();
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket?.receive();
      if (datagram == null) return;
      final message = parseSsdp(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      if (message == null) return;
      final device = classifySsdp(message);
      if (device != null) putBetterDevice(byHost, device);
    });
    // UDP is lossy: send the batch twice inside the window.
    await Future<void>.delayed(const Duration(seconds: 1));
    search();
    await Future<void>.delayed(const Duration(seconds: 2));
  } catch (_) {
    return;
  } finally {
    socket?.close();
  }
}

Future<void> _browse(String type, Map<String, FarlyDevice> byHost) async {
  final discovery = BonsoirDiscovery(type: type);
  StreamSubscription<BonsoirDiscoveryEvent>? subscription;
  try {
    await discovery.initialize();
    final events = discovery.eventStream;
    if (events == null) return;
    subscription = events.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          unawaited(
            event.service
                .resolve(discovery.serviceResolver)
                .catchError((Object _) {}),
          );
        case BonsoirDiscoveryServiceResolvedEvent():
          final service = event.service;
          final device = classifyService(
            type: service.type,
            name: service.name,
            host: _ipv4(service.hostAddresses),
            port: service.port,
            attributes: service.attributes,
          );
          if (device != null) putBetterDevice(byHost, device);
        default:
          break;
      }
    });
    await discovery.start();
    await Future<void>.delayed(const Duration(seconds: 3));
  } catch (_) {
    return;
  } finally {
    await subscription?.cancel();
    try {
      await discovery.stop();
    } catch (_) {
      // The search already ended.
    }
  }
}

Future<void> _broadlink(Map<String, FarlyDevice> byHost) async {
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final localIp = await _localIpv4() ?? '0.0.0.0';
    final packet = buildBroadlinkHello(
      localIp: localIp,
      localPort: socket.port,
    );
    void hello() =>
        socket?.send(packet, InternetAddress('255.255.255.255'), 80);
    hello();
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket?.receive();
      if (datagram == null) return;
      final hub = parseBroadlinkHello(datagram.data);
      if (hub == null) return;
      final host = datagram.address.address;
      if (host.contains(':')) return;
      putBetterDevice(
        byHost,
        FarlyDevice(
          id: FarlyDevice.idFor(DeviceBrand.broadlink, host),
          name: hub.name,
          kind: DeviceKind.climate,
          brand: DeviceBrand.broadlink,
          host: host,
          port: 80,
          source: 'broadlink',
        ),
      );
    });
    await Future<void>.delayed(const Duration(seconds: 1));
    hello();
    await Future<void>.delayed(const Duration(seconds: 1));
  } catch (_) {
    return;
  } finally {
    socket?.close();
  }
}

Future<void> _enrichNames(Map<String, FarlyDevice> byHost) async {
  final client = http.Client();
  final names = <String, String>{};
  try {
    await Future.wait(
      byHost.entries.map((entry) async {
        final name = await _lookupName(client, entry.value);
        if (name != null) names[entry.key] = name;
      }),
    );
  } finally {
    client.close();
  }
  for (final entry in names.entries) {
    final device = byHost[entry.key];
    if (device != null) {
      byHost[entry.key] = device.copyWith(name: entry.value);
    }
  }
}

Future<String?> _lookupName(http.Client client, FarlyDevice device) async {
  final host = device.host;
  if (host == null) return null;
  final Uri? uri;
  final List<String> tags;
  if (device.brand == DeviceBrand.roku) {
    uri = Uri.parse('http://$host:8060/query/device-info');
    tags = ['user-device-name', 'friendly-device-name'];
  } else if (device.descriptionUrl != null) {
    uri = Uri.tryParse(device.descriptionUrl!);
    tags = ['friendlyName'];
  } else {
    return null;
  }
  if (uri == null) return null;
  try {
    final response = await client
        .get(uri)
        .timeout(const Duration(milliseconds: 800));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    for (final tag in tags) {
      final value = xmlTag(response.body, tag);
      if (value != null) return value;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _ipv4(List<String> addresses) {
  for (final address in addresses) {
    final parsed = InternetAddress.tryParse(address);
    if (parsed != null &&
        parsed.type == InternetAddressType.IPv4 &&
        !parsed.isLoopback) {
      return parsed.address;
    }
  }
  return null;
}

Future<String?> _localIpv4() async {
  for (final interface in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) return address.address;
    }
  }
  return null;
}
