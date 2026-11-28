import 'package:farly/discovery/network_context.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/state/room_model.dart';
import 'package:farly/storage/device_store.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkFingerprint _net(String ssid) => NetworkFingerprint(
  key: 'ssid:$ssid',
  label: ssid,
  ssidKey: 'ssid:$ssid',
  subnetKey: 'subnet:192.168.1',
);

FarlyDevice _tv(String name, int last) => FarlyDevice(
  id: 'roku@192.168.1.$last',
  name: name,
  kind: DeviceKind.screen,
  brand: DeviceBrand.roku,
  host: '192.168.1.$last',
  port: 8060,
  networkKeys: const ['ssid:Home'],
);

void main() {
  late FarlyDevice a;
  late FarlyDevice b;
  late NetworkFingerprint net;
  late RoomModel room;

  setUp(() async {
    a = _tv('Living room', 20);
    b = _tv('Bedroom', 21);
    net = _net('Home');
    room = RoomModel(
      store: MemoryDeviceStore([a, b]),
      scanDevices: () async => const [],
      readNetwork: () async => net,
    );
    await room.load();
  });

  test('markConnected narrows Home but not devicesOnNetwork', () async {
    expect(room.homeDevices, hasLength(2));
    await room.markConnected(a);
    expect(room.homeDevices.map((d) => d.id), [a.id]);
    expect(room.devicesOnNetwork, hasLength(2));
  });

  test('a scan clears the focus', () async {
    await room.markConnected(a);
    await room.scan();
    expect(room.focusedId, isNull);
    expect(room.homeDevices, hasLength(2));
  });

  test('forgetting the focused TV clears it', () async {
    await room.markConnected(a);
    await room.forget(a);
    expect(room.focusedId, isNull);
    expect(room.homeDevices.map((d) => d.id), [b.id]);
  });

  test('a Wi-Fi change clears it', () async {
    await room.markConnected(a);
    net = _net('Other');
    await room.refreshNetwork();
    expect(room.focusedId, isNull);
  });
}
