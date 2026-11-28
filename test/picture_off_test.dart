import 'package:farly/app.dart';
import 'package:farly/control/lg_session.dart';
import 'package:farly/control/remote_session.dart';
import 'package:farly/control/roku_session.dart';
import 'package:farly/discovery/network_context.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/remote_action.dart';
import 'package:farly/models/remote_layout.dart';
import 'package:farly/storage/device_store.dart';
import 'package:farly/storage/layout_store.dart';
import 'package:farly/storage/shortcut_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _roku = FarlyDevice(
  id: 'roku@192.168.1.20',
  name: 'Living room',
  kind: DeviceKind.screen,
  brand: DeviceBrand.roku,
  host: '192.168.1.20',
  networkKeys: ['ssid:Test'],
  port: 8060,
);

Future<NetworkFingerprint?> _network() async => const NetworkFingerprint(
  key: 'ssid:Test',
  label: 'Test',
  ssidKey: 'ssid:Test',
  subnetKey: 'subnet:192.168.1',
);

void main() {
  test('LG turns the screen off with active standby', () async {
    final calls = <String>[];
    final payloads = <Map<String, dynamic>>[];
    final result = await lgSetScreen((uri, payload) async {
      calls.add(uri);
      payloads.add(payload);
      return {'type': 'response', 'payload': {'returnValue': true}};
    }, off: true);
    expect(result.ok, isTrue);
    expect(calls, ['ssap://com.webos.service.tvpower/power/turnOffScreen']);
    expect(payloads, [
      {'standbyMode': 'active'},
    ]);
  });

  test('LG falls back to the webOS 4 path and turns the screen on', () async {
    final uris = <String>[];
    final result = await lgSetScreen((uri, payload) async {
      uris.add(uri);
      return uri.contains('tvpower')
          ? {'type': 'error', 'error': '404 no such service or method'}
          : {'type': 'response', 'payload': {'returnValue': true}};
    }, off: false);
    expect(result.ok, isTrue);
    expect(uris, [
      'ssap://com.webos.service.tvpower/power/turnOnScreen',
      'ssap://com.webos.service.tv.power/turnOnScreen',
    ]);
  });

  test('LG reports failure when both paths error', () async {
    final result = await lgSetScreen(
      (uri, payload) async => {'type': 'error'},
      off: true,
    );
    expect(result.ok, isFalse);
  });

  Future<(RokuSession, List<String>)> openRoku(String body) async {
    final paths = <String>[];
    final session = RokuSession(
      device: _roku,
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(body, 200);
      }),
    );
    await session.open();
    return (session, paths);
  }

  test('Roku sends Info for TVs only', () async {
    final (tv, tvPaths) = await openRoku('<is-tv>true</is-tv>');
    expect(tv.pictureOffSupport, PictureOffSupport.menu);
    final result = await tv.setPictureOff(off: true);
    expect(result.ok, isTrue);
    expect(result.detail, 'Choose Turn off screen on the TV');
    expect(tvPaths, contains('/keypress/Info'));

    final (stick, stickPaths) = await openRoku('<is-tv>false</is-tv>');
    expect(stick.pictureOffSupport, PictureOffSupport.none);
    expect((await stick.setPictureOff(off: true)).ok, isFalse);
    expect(stickPaths, isNot(contains('/keypress/Info')));
  });

  test('a layout saved before Picture off loads and gains the key', () {
    final old = RemoteLayout.fromJson(const {
      'blocks': ['pad', 'chrome'],
      'chrome': ['home', 'back'],
    });
    expect(old.chrome, [ChromeId.home, ChromeId.back, ChromeId.pictureOff]);
    // A saved v2 layout that hid it stays hidden.
    final hidden = RemoteLayout.fromJson(
      const RemoteLayout(
        blocks: [RemoteBlockId.pad, RemoteBlockId.chrome],
        chrome: [ChromeId.home],
      ).toJson(),
    );
    expect(hidden.chrome, [ChromeId.home]);
  });

  Future<void> openRemote(WidgetTester tester, RemoteSession session) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _network,
        store: MemoryDeviceStore([_roku]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => session,
        shortcuts: MemoryShortcutStore(),
        layout: MemoryLayoutStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();
  }

  testWidgets('Picture off is hidden when the TV cannot do it', (tester) async {
    await openRemote(tester, _FakeSession(PictureOffSupport.none));
    expect(find.bySemanticsLabel('Picture off'), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsWidgets);
  });

  testWidgets('Picture off toggles on a direct TV', (tester) async {
    final session = _FakeSession(PictureOffSupport.direct);
    await openRemote(tester, session);
    expect(find.byIcon(Icons.tv_off_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tv_off_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tv_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Picture on'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tv_rounded));
    await tester.pumpAndSettle();
    expect(session.requests, [true, false]);
    expect(find.byIcon(Icons.tv_off_rounded), findsOneWidget);
  });
}

class _FakeSession extends RemoteSession {
  _FakeSession(this.support);

  final PictureOffSupport support;
  final requests = <bool>[];
  final _updates = SessionUpdates();

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  PictureOffSupport get pictureOffSupport => support;

  @override
  Future<CommandResult> setPictureOff({required bool off}) async {
    requests.add(off);
    return const CommandResult(true);
  }

  @override
  Future<void> open() async {
    _updates.add(const SessionUpdate(SessionPhase.ready, detail: 'Connected'));
  }

  @override
  Future<CommandResult> send(RemoteAction action) async =>
      const CommandResult(true);

  @override
  Future<void> close() => _updates.close();
}
