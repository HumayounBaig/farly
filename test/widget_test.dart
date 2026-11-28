import 'package:farly/app.dart';
import 'package:farly/control/remote_session.dart';
import 'package:farly/discovery/network_context.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/remote_action.dart';
import 'package:farly/models/remote_layout.dart';
import 'package:farly/models/stream_app.dart';
import 'package:farly/storage/device_store.dart';
import 'package:farly/storage/layout_store.dart';
import 'package:farly/storage/shortcut_store.dart';
import 'package:farly/widgets/horizon_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<NetworkFingerprint?> _testNetwork() async => const NetworkFingerprint(
  key: 'ssid:Test',
  label: 'Test',
  ssidKey: 'ssid:Test',
  subnetKey: 'subnet:192.168.1',
);

void main() {
  testWidgets('scan notice and preview pad', (tester) async {
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Living room',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
            networkKeys: ['ssid:Test'],
            port: 8060,
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => NotedSession(
          phase: SessionPhase.limited,
          detail: 'Preview. Nothing is connected.',
          preview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan the room'), findsOneWidget);
    expect(find.text('Living room'), findsOneWidget);

    await tester.tap(find.text('Scan the room'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing answered.'), findsOneWidget);

    await tester.tap(find.text('Preview the pad'));
    await tester.pumpAndSettle();
    expect(find.text('Preview. Nothing is connected.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(RemoteAction.volumeUp)));
    await tester.pumpAndSettle();
    expect(find.text('Would send Volume up'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Type on the TV'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Would type'), findsOneWidget);
  });

  testWidgets('hold a device to rename it and pick an icon', (tester) async {
    final store = MemoryDeviceStore([
      const FarlyDevice(
        id: 'roku@192.168.1.20',
        name: 'Living room',
        kind: DeviceKind.screen,
        brand: DeviceBrand.roku,
        host: '192.168.1.20',
        networkKeys: ['ssid:Test'],
        port: 8060,
      ),
    ]);
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: store,
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => NotedSession(
          phase: SessionPhase.limited,
          detail: 'Preview. Nothing is connected.',
          preview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Living room'));
    await tester.pumpAndSettle();
    expect(find.text('Rename or change icon'), findsOneWidget);
    await tester.tap(find.text('Rename or change icon'));
    await tester.pumpAndSettle();
    expect(find.text('Edit device'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Den');
    await tester.tap(find.text('🛋️'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Den'), findsOneWidget);
    final saved = await store.read();
    expect(saved.single.name, 'Den');
    expect(saved.single.icon, 'emoji:sofa');
    expect(saved.single.nameLocked, isTrue);
  });

  testWidgets('pad asks for the TV code and unlocks after pairing', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final session = _PairingSession();
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'androidTv@192.168.1.30',
            name: 'TCL C6K',
            kind: DeviceKind.screen,
            brand: DeviceBrand.androidTv,
            host: '192.168.1.30',
            networkKeys: ['ssid:Test'],
            port: 6466,
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => session,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TCL C6K'));
    await tester.pumpAndSettle();

    expect(find.text('Pair with the TV'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(RemoteAction.volumeDown)));
    await tester.pump();
    expect(find.text('Enter the code shown on the TV first.'), findsOneWidget);
    expect(session.sent, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('pairing-code')),
      'a1b2c3',
    );
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(session.codes, ['A1B2C3']);
    expect(find.text('Pair with the TV'), findsNothing);
    expect(find.text('Connected'), findsNothing);
    expect(find.bySemanticsLabel('Connected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(RemoteAction.volumeUp)));
    await tester.pumpAndSettle();
    expect(
      session.sent,
      List.filled(2, RemoteAction.volumeUp),
    );
  });

  testWidgets('a connected remote reopens on the next launch', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const tv = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'TCL C6K',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
      networkKeys: ['ssid:Test'],
      port: 6466,
    );
    final store = MemoryDeviceStore([tv]);

    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: store,
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Tap the pencil or hold a device to rename it, change its icon, or delete it.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('All saved devices'), findsWidgets);
    expect(await store.readLastConnected(), isNull);

    await tester.tap(find.text('TCL C6K'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsNothing);
    expect(find.bySemanticsLabel('Connected'), findsOneWidget);
    expect(await store.readLastConnected(), tv.id);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        key: UniqueKey(),
        store: store,
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsNothing);
    expect(find.bySemanticsLabel('Connected'), findsOneWidget);
    expect(find.text('Back to devices'), findsNothing);
    expect(find.bySemanticsLabel('Back to devices'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back to devices'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Tap the pencil or hold a device to rename it, change its icon, or delete it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sidebar lists every saved device across Wi‑Fi', (tester) async {
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: () async => const NetworkFingerprint(
          key: 'ssid:Cafe',
          label: 'Cafe',
          ssidKey: 'ssid:Cafe',
          subnetKey: 'subnet:10.0.0',
        ),
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Home TV',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
            networkKeys: ['ssid:Home', 'subnet:192.168.1'],
          ),
          const FarlyDevice(
            id: 'androidTv@10.0.0.8',
            name: 'Cafe TV',
            kind: DeviceKind.screen,
            brand: DeviceBrand.androidTv,
            host: '10.0.0.8',
            networkKeys: ['ssid:Cafe', 'subnet:10.0.0'],
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cafe TV'), findsOneWidget);
    expect(find.text('Home TV'), findsNothing);
    expect(find.bySemanticsLabel('All saved devices'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('All saved devices').first);
    await tester.pumpAndSettle();

    expect(find.text('All saved devices'), findsWidgets);
    expect(find.text('On this Wi‑Fi'), findsOneWidget);
    expect(find.text('Other Wi‑Fi'), findsOneWidget);
    expect(find.text('Cafe TV'), findsWidgets);
    expect(find.text('Home TV'), findsOneWidget);
    expect(find.text('Saved on Home'), findsOneWidget);
  });

  testWidgets('pencil opens rename sheet and saves the name', (tester) async {
    final store = MemoryDeviceStore([
      const FarlyDevice(
        id: 'roku@192.168.1.20',
        name: 'Living room',
        kind: DeviceKind.screen,
        brand: DeviceBrand.roku,
        host: '192.168.1.20',
        networkKeys: ['ssid:Test'],
        port: 8060,
      ),
    ]);
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: store,
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => NotedSession(
          phase: SessionPhase.limited,
          detail: 'Preview. Nothing is connected.',
          preview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Edit device'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Den TV');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Den TV'), findsOneWidget);
    final saved = await store.read();
    expect(saved.single.name, 'Den TV');
    expect(saved.single.nameLocked, isTrue);
  });

  testWidgets('hold an app button to switch Netflix to Disney+', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final shortcuts = MemoryShortcutStore();
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Living room',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
            networkKeys: ['ssid:Test'],
            port: 8060,
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
        shortcuts: shortcuts,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    await tester.longPress(find.text('Netflix'));
    await tester.pumpAndSettle();
    expect(find.text('App button 1'), findsOneWidget);
    await tester.tap(find.text('Disney+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Disney+'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
    final slots = await shortcuts.read();
    expect(slots.first.appId, 'disney');
  });

  testWidgets('address sheet rejects a bad address', (tester) async {
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore(),
        scanDevices: () async => const [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add by address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'not-an-ip');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter an IPv4 address.'), findsOneWidget);
  });

  testWidgets('hold the pad to rearrange, hide chrome, edit apps, reset', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final layout = MemoryLayoutStore();
    final shortcuts = MemoryShortcutStore();
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Living room',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
            networkKeys: ['ssid:Test'],
            port: 8060,
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
        shortcuts: shortcuts,
        layout: layout,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(HorizonPad));
    // Jiggle repeats forever, so avoid pumpAndSettle while arranging.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Arrange mode'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Hide Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hidden — tap to show'), findsOneWidget);

    expect(find.bySemanticsLabel('Hide Play controls'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Hide Play controls'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final afterHide = await layout.read();
    expect(
      afterHide.blocks,
      isNot(contains(RemoteBlockId.transport)),
      reason: 'blocks=${afterHide.blocks}',
    );
    expect(find.bySemanticsLabel('Show Play controls'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Move Apps down'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect((await layout.read()).blocks.indexOf(RemoteBlockId.shortcuts), 2);

    await tester.tap(find.text('Netflix'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('App button 1'), findsOneWidget);
    await tester.tap(find.text('Disney+'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Disney+'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Netflix'), findsOneWidget);
    expect(await layout.read(), RemoteLayout.defaults);
    expect((await shortcuts.read()).first.appId, 'netflix');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Arrange mode'), findsNothing);
    expect(find.text('Roku'), findsOneWidget);
  });

  testWidgets('arrange icon opens edit when pad is hidden', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final layout = MemoryLayoutStore(
      const RemoteLayout(
        blocks: [RemoteBlockId.powerRow, RemoteBlockId.chrome],
        chrome: [ChromeId.home, ChromeId.back],
      ),
    );
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Living room',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
            networkKeys: ['ssid:Test'],
            port: 8060,
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
        shortcuts: MemoryShortcutStore(),
        layout: layout,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();

    expect(await layout.read(), isA<RemoteLayout>().having(
      (value) => value.blocks,
      'blocks',
      isNot(contains(RemoteBlockId.pad)),
    ));
    expect(find.text('Arrange mode'), findsNothing);
    expect(find.bySemanticsLabel('Arrange remote'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Arrange remote'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Arrange mode'), findsOneWidget);
    expect(find.text('Hidden — tap to show'), findsWidgets);
    expect(find.bySemanticsLabel('Show D-pad'), findsOneWidget);
  });
}

class _ReadySession extends RemoteSession {
  final _updates = SessionUpdates();

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  List<AppShortcut> get shortcuts => [
    StreamApp.netflix.shortcutFor(DeviceBrand.roku),
    StreamApp.youtube.shortcutFor(DeviceBrand.roku),
  ];

  @override
  Future<void> open() async {
    _updates.add(const SessionUpdate(SessionPhase.ready, detail: 'Connected'));
  }

  @override
  Future<CommandResult> send(RemoteAction action) async =>
      const CommandResult(true);

  @override
  Future<CommandResult> launch(AppShortcut shortcut) async =>
      const CommandResult(true);

  @override
  Future<void> close() => _updates.close();
}

class _PairingSession extends RemoteSession {
  final _updates = SessionUpdates();
  final codes = <String>[];
  final sent = <RemoteAction>[];

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  Future<void> open() async {
    _updates.add(
      const SessionUpdate(
        SessionPhase.pairing,
        detail: 'Enter the code shown on the TV.',
      ),
    );
  }

  @override
  Future<CommandResult> submitCode(String code) async {
    codes.add(code);
    _updates.add(const SessionUpdate(SessionPhase.ready, detail: 'Connected'));
    return const CommandResult(true);
  }

  @override
  Future<CommandResult> send(RemoteAction action) async {
    sent.add(action);
    return const CommandResult(true);
  }

  @override
  Future<void> close() => _updates.close();
}
