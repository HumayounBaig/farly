import 'dart:convert';

import 'package:farly/models/farly_device.dart';
import 'package:farly/state/room_model.dart';
import 'package:farly/storage/device_store.dart';
import 'package:farly/sync/device_sync.dart';
import 'package:farly/sync/sync_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('parseSyncEndpoint requires host:port', () {
    expect(parseSyncEndpoint('192.168.1.20:41234')?.host, '192.168.1.20');
    expect(parseSyncEndpoint('192.168.1.20:41234')?.port, 41234);
    expect(parseSyncEndpoint('192.168.1.20'), isNull);
    expect(parseSyncEndpoint('not-an-ip:80'), isNull);
  });

  const living = FarlyDevice(
    id: 'samsung@192.168.1.40',
    name: 'Living room',
    kind: DeviceKind.screen,
    brand: DeviceBrand.samsung,
    host: '192.168.1.40',
    port: 8002,
    token: 'phone-token',
    networkKeys: ['ssid:Home'],
  );

  test('payload round-trips through JSON', () {
    final payload = DeviceSyncPayload(
      devices: const [living],
      lastConnectedId: living.id,
      lastConnectedByNetwork: const {'ssid:Home': 'samsung@192.168.1.40'},
      source: 'ios',
    );
    final copy = DeviceSyncPayload.fromJson(
      jsonDecode(jsonEncode(payload.toJson())) as Map<String, dynamic>,
    );
    expect(copy.devices.single.token, 'phone-token');
    expect(copy.lastConnectedId, living.id);
    expect(copy.lastConnectedByNetwork['ssid:Home'], living.id);
  });

  test('import prefers phone credentials and keeps a locked name', () {
    final local = living.copyWith(
      name: 'Lounge',
      nameLocked: true,
      token: 'old',
      clearClientKey: true,
    );
    final imported = living.copyWith(
      name: 'Living room',
      token: 'fresh',
      clientKey: 'key',
    );
    final merged = mergeImportedDevices(local: [local], imported: [imported]);
    expect(merged, hasLength(1));
    expect(merged.single.name, 'Lounge');
    expect(merged.single.token, 'fresh');
    expect(merged.single.clientKey, 'key');
  });

  test('RoomModel import writes devices and last-connected map', () async {
    final room = RoomModel(
      store: MemoryDeviceStore([living.copyWith(token: 'stale')]),
      scanDevices: () async => const [],
      readNetwork: () async => null,
    );
    await room.load();

    final result = await room.importSyncPayload(
      DeviceSyncPayload(
        devices: [
          living.copyWith(token: 'synced'),
          const FarlyDevice(
            id: 'roku@192.168.1.22',
            name: 'Bedroom',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.22',
            port: 8060,
          ),
        ],
        lastConnectedId: living.id,
        lastConnectedByNetwork: const {'ssid:Home': 'samsung@192.168.1.40'},
      ),
    );

    expect(result.added, 1);
    expect(result.updated, 1);
    expect(room.devices, hasLength(2));
    expect(room.devices.firstWhere((d) => d.id == living.id).token, 'synced');
    expect(room.lastConnectedId, living.id);
    expect(room.lastConnectedByNetwork['ssid:Home'], living.id);
  });

  test('sync server answers only with the correct PIN', () async {
    final server = FarlySyncServer();
    addTearDown(server.stop);
    await server.start(
      const DeviceSyncPayload(devices: [living], source: 'test'),
      ttl: const Duration(seconds: 30),
    );
    expect(server.port, isNotNull);

    final wrongPin = server.pin == '999999' ? '000000' : '999999';
    final denied = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}$farlySyncPath'),
      headers: {farlySyncPinHeader: wrongPin},
    );
    expect(denied.statusCode, 401);

    final ok = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}$farlySyncPath'),
      headers: {farlySyncPinHeader: server.pin},
    );
    expect(ok.statusCode, 200);
    final payload = DeviceSyncPayload.fromJson(
      jsonDecode(ok.body) as Map<String, dynamic>,
    );
    expect(payload.devices.single.id, living.id);
  });

  test('constantTimeEquals compares length and content', () {
    expect(constantTimeEquals('123456', '123456'), isTrue);
    expect(constantTimeEquals('123456', '123457'), isFalse);
    expect(constantTimeEquals('12345', '123456'), isFalse);
  });

  test(
    'sync server stops after repeated wrong PINs and ignores ?pin=',
    () async {
      final server = FarlySyncServer();
      addTearDown(server.stop);
      await server.start(
        const DeviceSyncPayload(devices: [living], source: 'test'),
        ttl: const Duration(seconds: 30),
      );
      final url = 'http://127.0.0.1:${server.port}$farlySyncPath';
      final query = await http.get(Uri.parse('$url?pin=${server.pin}'));
      expect(query.statusCode, 401);
      for (var i = 0; i < maxSyncPinFailures - 1; i++) {
        await http.get(Uri.parse(url), headers: {farlySyncPinHeader: 'nope'});
      }
      expect(server.isRunning, isFalse);
    },
  );

  test(
    'parallel wrong PINs lock the share before the correct PIN works',
    () async {
      final server = FarlySyncServer();
      addTearDown(server.stop);
      await server.start(
        const DeviceSyncPayload(devices: [living], source: 'test'),
        ttl: const Duration(seconds: 30),
      );
      final url = Uri.parse('http://127.0.0.1:${server.port}$farlySyncPath');
      final pin = server.pin;
      await Future.wait([
        for (var i = 0; i < 50; i++)
          http
              .get(url, headers: {farlySyncPinHeader: 'x$i'})
              .catchError((_) => http.Response('', 599)),
      ]);
      final late = await http
          .get(url, headers: {farlySyncPinHeader: pin})
          .catchError((_) => http.Response('', 599));
      expect(late.statusCode, isNot(200));
    },
  );
}
