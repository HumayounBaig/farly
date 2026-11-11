import 'dart:convert';

import 'package:farly/control/remote_session.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/remote_action.dart';
import 'package:farly/state/remote_controller.dart';
import 'package:farly/state/room_model.dart';
import 'package:farly/storage/device_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tv = FarlyDevice(
  id: 'roku@192.168.1.20',
  name: 'Den',
  kind: DeviceKind.screen,
  brand: DeviceBrand.roku,
  host: '192.168.1.20',
);

void main() {
  test(
    'a stored device from another version is skipped, not the list',
    () async {
      final valid = _tv.toJson();
      final future = {..._tv.toJson(), 'id': 'x', 'brand': 'futureBrand'};
      final badKind = {..._tv.toJson(), 'id': 'y', 'kind': 'hologram'};
      SharedPreferences.setMockInitialValues({
        'farly.devices': '[${_json(valid)},${_json(future)},${_json(badKind)}]',
      });
      final devices = await PreferencesDeviceStore().read();
      expect(devices.map((d) => d.id), [_tv.id]);
    },
  );

  test('the first empty scan retries once, later empty scans do not', () async {
    var calls = 0;
    final model = RoomModel(
      store: MemoryDeviceStore(),
      scanDevices: () async {
        calls += 1;
        return calls == 2 ? [_tv] : const [];
      },
      retryDelay: Duration.zero,
    );
    await model.scan();
    expect(calls, 2);
    expect(model.devices, hasLength(1));
    expect(model.notice, isNull);

    calls = 10;
    await model.scan();
    expect(calls, 11);
    expect(model.notice, contains('Local Network'));
  });

  test('a remote popped mid-send does not notify after dispose', () async {
    final controller = RemoteController(
      device: _tv,
      onCredentials: (_) {},
      sessions: (device, sink) =>
          NotedSession(phase: SessionPhase.ready, detail: 'No device'),
    );
    await controller.connect();
    await Future<void>.delayed(Duration.zero);
    final pending = controller.launch(
      AppShortcut.plain('YouTube', 'https://www.youtube.com'),
    );
    controller.dispose();
    await pending;
  });

  test('updateDevice replaces a row that only shares host history', () async {
    const saved = FarlyDevice(
      id: 'androidTv@192.168.1.20',
      name: 'Android TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.20',
      token: 'cert',
      clientKey: 'key',
      hosts: ['192.168.1.20', '192.168.1.80'],
    );
    final model = RoomModel(store: MemoryDeviceStore([saved]));
    await model.load();
    await model.updateDevice(
      const FarlyDevice(
        id: 'androidTv@192.168.1.80',
        name: 'Android TV',
        kind: DeviceKind.screen,
        brand: DeviceBrand.androidTv,
        host: '192.168.1.80',
        token: 'cert',
        clientKey: 'key',
        hosts: ['192.168.1.80', '192.168.1.20'],
      ),
    );
    expect(model.devices, hasLength(1));
    expect(model.devices.single.host, '192.168.1.80');
    expect(model.devices.single.token, 'cert');
  });

  test('markConnected uses the live rebound device for auto-open', () async {
    const opened = FarlyDevice(
      id: 'roku@192.168.1.20',
      name: 'Den',
      kind: DeviceKind.screen,
      brand: DeviceBrand.roku,
      host: '192.168.1.20',
      hosts: ['192.168.1.20', '192.168.1.80'],
    );
    final live = opened.copyWith(host: '192.168.1.80');
    final store = MemoryDeviceStore([opened]);
    final model = RoomModel(store: store);
    await model.load();
    await model.updateDevice(live);
    await model.markConnected(live);
    expect(model.lastConnected?.host, '192.168.1.80');

    final again = RoomModel(store: store);
    await again.load();
    expect(again.takeAutoOpen()?.host, '192.168.1.80');
  });

  test('relocate updates a saved TV that answered on a new address', () async {
    const saved = FarlyDevice(
      id: 'roku@192.168.1.20',
      name: 'Den',
      kind: DeviceKind.screen,
      brand: DeviceBrand.roku,
      host: '192.168.1.20',
      uid: 'roku-yn00',
    );
    final model = RoomModel(
      store: MemoryDeviceStore([saved]),
      scanDevices: () async => [
        const FarlyDevice(
          id: 'roku@192.168.1.80',
          name: 'Den',
          kind: DeviceKind.screen,
          brand: DeviceBrand.roku,
          host: '192.168.1.80',
          uid: 'roku-yn00',
        ),
      ],
    );
    await model.load();
    final moved = await model.relocate(saved);
    expect(moved?.host, '192.168.1.80');
    expect(model.devices.single.host, '192.168.1.80');
    expect(
      model.devices.single.candidateHosts,
      containsAll(['192.168.1.80', '192.168.1.20']),
    );
  });

  test(
    'remote tries a remembered address when the saved one is dead',
    () async {
      final opened = <String>[];
      final device = FarlyDevice(
        id: 'roku@192.168.1.20',
        name: 'Den',
        kind: DeviceKind.screen,
        brand: DeviceBrand.roku,
        host: '192.168.1.20',
        hosts: const ['192.168.1.20', '192.168.1.80'],
      );
      final controller = RemoteController(
        device: device,
        onCredentials: (_) {},
        sessions: (device, sink) => _HostAwareSession(opened),
      );
      await controller.connect();
      expect(opened, ['192.168.1.20', '192.168.1.80']);
      expect(controller.phase, SessionPhase.ready);
      expect(controller.device.host, '192.168.1.80');
      expect(controller.device.id, 'roku@192.168.1.20');
      controller.dispose();
    },
  );
}

class _HostAwareSession extends RemoteSession {
  _HostAwareSession(this.opened);

  final List<String> opened;
  FarlyDevice device = const FarlyDevice(
    id: 'x',
    name: 'x',
    kind: DeviceKind.screen,
    brand: DeviceBrand.roku,
  );
  final _updates = SessionUpdates();

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  void rebind(FarlyDevice next) => device = next;

  @override
  Future<void> open() async {
    final host = device.host ?? '';
    opened.add(host);
    if (host == '192.168.1.80') {
      _updates.add(
        const SessionUpdate(SessionPhase.ready, detail: 'Connected'),
      );
      return;
    }
    _updates.add(
      const SessionUpdate(SessionPhase.failed, detail: 'Unreachable'),
    );
  }

  @override
  Future<CommandResult> send(RemoteAction action) async =>
      const CommandResult(true);

  @override
  Future<void> close() => _updates.close();
}

String _json(Map<String, dynamic> map) => jsonEncode(map);
