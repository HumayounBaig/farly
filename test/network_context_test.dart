import 'package:farly/discovery/network_context.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/state/room_model.dart';
import 'package:farly/storage/device_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subnetKeyForHost keeps the /24 prefix', () {
    expect(subnetKeyForHost('192.168.1.40'), 'subnet:192.168.1');
    expect(subnetKeyForHost('10.0.0.2'), 'subnet:10.0.0');
    expect(subnetKeyForHost('bad'), isNull);
  });

  test('fingerprint prefers SSID and still stamps the subnet', () {
    const network = NetworkFingerprint(
      key: 'ssid:Home',
      label: 'Home',
      ssidKey: 'ssid:Home',
      subnetKey: 'subnet:192.168.1',
    );
    expect(network.stampKeys, ['ssid:Home', 'subnet:192.168.1']);
    expect(network.matches(['ssid:Home']), isTrue);
    expect(network.matches(['subnet:192.168.1']), isTrue);
    expect(network.matches(['ssid:Cafe']), isFalse);
  });

  test('room hides devices that belong to another Wi-Fi', () async {
    const home = FarlyDevice(
      id: 'roku@192.168.1.20',
      name: 'Home TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.roku,
      host: '192.168.1.20',
      networkKeys: ['ssid:Home', 'subnet:192.168.1'],
    );
    const cafe = FarlyDevice(
      id: 'androidTv@10.0.0.8',
      name: 'Cafe TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '10.0.0.8',
      networkKeys: ['ssid:Cafe', 'subnet:10.0.0'],
    );
    final model = RoomModel(
      store: MemoryDeviceStore([home, cafe]),
      readNetwork: () async => const NetworkFingerprint(
        key: 'ssid:Cafe',
        label: 'Cafe',
        ssidKey: 'ssid:Cafe',
        subnetKey: 'subnet:10.0.0',
      ),
    );
    await model.load();
    expect(model.devicesOnNetwork.map((d) => d.name), ['Cafe TV']);
    expect(model.devicesElsewhere.map((d) => d.name), ['Home TV']);
  });

  test('auto-open only resumes the remote saved for this Wi-Fi', () async {
    const home = FarlyDevice(
      id: 'roku@192.168.1.20',
      name: 'Home TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.roku,
      host: '192.168.1.20',
      networkKeys: ['ssid:Home', 'subnet:192.168.1'],
    );
    const cafe = FarlyDevice(
      id: 'androidTv@10.0.0.8',
      name: 'Cafe TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '10.0.0.8',
      networkKeys: ['ssid:Cafe', 'subnet:10.0.0'],
    );
    final store = MemoryDeviceStore(
      [home, cafe],
      home.id,
      {'ssid:Home': home.id, 'ssid:Cafe': cafe.id},
    );
    final model = RoomModel(
      store: store,
      readNetwork: () async => const NetworkFingerprint(
        key: 'ssid:Cafe',
        label: 'Cafe',
        ssidKey: 'ssid:Cafe',
        subnetKey: 'subnet:10.0.0',
      ),
    );
    await model.load();
    expect(model.takeAutoOpen()?.id, cafe.id);
  });

  test('markConnected stamps the current network and remembers per Wi-Fi', () async {
    const tv = FarlyDevice(
      id: 'roku@192.168.1.20',
      name: 'Den',
      kind: DeviceKind.screen,
      brand: DeviceBrand.roku,
      host: '192.168.1.20',
    );
    final store = MemoryDeviceStore([tv]);
    final model = RoomModel(
      store: store,
      readNetwork: () async => const NetworkFingerprint(
        key: 'ssid:Home',
        label: 'Home',
        ssidKey: 'ssid:Home',
        subnetKey: 'subnet:192.168.1',
      ),
    );
    await model.load();
    await model.markConnected(tv);
    expect(model.devices.single.networkKeys, contains('ssid:Home'));
    expect(model.lastConnectedByNetwork['ssid:Home'], tv.id);
    expect(await store.readLastConnected(), tv.id);
  });
}
