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
      const AppShortcut('YouTube', 'https://www.youtube.com'),
    );
    controller.dispose();
    await pending;
  });
}

String _json(Map<String, dynamic> map) => jsonEncode(map);
