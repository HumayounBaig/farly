import 'dart:async';

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
import 'package:farly/widgets/farly_list.dart';
import 'package:farly/widgets/horizon_pad.dart';
import 'package:farly/widgets/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<NetworkFingerprint?> _testNetwork() async => const NetworkFingerprint(
  key: 'ssid:Test',
  label: 'Test',
  ssidKey: 'ssid:Test',
  subnetKey: 'subnet:192.168.1',
);

void main() {
  testWidgets('empty-on-network home shows one Saved TVs entry', (tester) async {
    await tester.pumpWidget(
      FarlyApp(
        readNetwork: () async => const NetworkFingerprint(
          key: 'subnet:10.0.0',
          label: '10.0.0.x',
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
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => _ReadySession(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved TVs'), findsOneWidget);
    expect(find.text('1 saved · 1 on another Wi‑Fi'), findsOneWidget);
    expect(find.text('This Wi‑Fi'), findsOneWidget);
    expect(find.text('10.0.0.x'), findsNothing);
  });

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
    expect(find.textContaining('Would type'), findsWidgets); // page + sheet
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
    expect(session.sent, List.filled(2, RemoteAction.volumeUp));
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
        'Tap the three dots or hold a device to rename it, change its icon, or delete it.',
      ),
      findsOneWidget,
    );
    expect(find.text('Saved TVs'), findsOneWidget);
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
        'Tap the three dots or hold a device to rename it, change its icon, or delete it.',
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
    expect(find.text('Saved TVs'), findsOneWidget);

    await tester.tap(find.text('Saved TVs'));
    await tester.pumpAndSettle();

    expect(find.text('Saved TVs'), findsNWidgets(2)); // home row + drawer title
    expect(find.text('Cafe · 1 here'), findsOneWidget);
    expect(find.text('On this Wi‑Fi'), findsNWidgets(2)); // home + drawer
    expect(find.text('Other Wi‑Fi'), findsOneWidget);
    expect(find.text('Cafe TV'), findsWidgets);
    expect(find.text('Home TV'), findsOneWidget);
    expect(find.text('Saved on Home'), findsOneWidget);
  });

  testWidgets('sidebar rows delete by swipe or long-press', (tester) async {
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
        sessions: (device, onCredentials) => _ReadySession(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved TVs'));
    await tester.pumpAndSettle();
    expect(find.text('Saved TVs'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(FarlyListRow),
      ),
      findsWidgets,
    );
    expect(find.text('Test · 1 here'), findsOneWidget);
    final row = find.descendant(
      of: find.byType(Drawer),
      matching: find.text('Living room'),
    );
    expect(row, findsOneWidget);

    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Rename or change icon'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Living room?'), findsOneWidget);
  });

  testWidgets('sidebar swipe asks to delete', (tester) async {
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
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved TVs'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Living room'),
      ),
      const Offset(-250, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete Living room?'), findsOneWidget);
  });

  testWidgets('three dots open the actions sheet and rename saves', (
    tester,
  ) async {
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
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    // Exact label: the button is its own node, not merged into the row.
    expect(
      find.bySemanticsLabel(RegExp(r'^More options for Living room$')),
      findsOneWidget,
    );
    final dots = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^More options for Living room$')),
    );
    expect(dots.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Rename or change icon'));
    await tester.pumpAndSettle();
    expect(find.text('Edit device'), findsOneWidget);
    semantics.dispose();
    await tester.enterText(find.byType(TextField).first, 'Den TV');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Den TV'), findsOneWidget);
    final saved = await store.read();
    expect(saved.single.name, 'Den TV');
    expect(saved.single.nameLocked, isTrue);
  });

  testWidgets('hold an app button to switch Netflix to Disney+', (
    tester,
  ) async {
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Arrange remote'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // Static preview only: one (inert) pad, plus one row per block.
    expect(find.byType(HorizonPad), findsOneWidget);
    expect(find.byType(FarlyListRow), findsWidgets);
    expect(find.text('D-pad'), findsOneWidget);
    expect(find.text('Reset to default'), findsOneWidget);

    // Hiding a block removes it from the preview.
    expect(find.text('Netflix'), findsWidgets);
    final padRows = find.byType(HorizonPad);
    expect(padRows, findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Hide Play controls'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final afterHide = await layout.read();
    expect(afterHide.blocks, isNot(contains(RemoteBlockId.transport)));
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.bySemanticsLabel('Show Play controls'), findsOneWidget);

    // Menu keys: per-key toggle lives in a sub-sheet.
    await tester.tap(find.bySemanticsLabel('Edit Menu keys'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Hide Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await layout.read()).chrome, isNot(contains(ChromeId.back)));
    expect(find.bySemanticsLabel('Show Back'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Apps: edit a shortcut from the sub-sheet.
    await tester.tap(find.bySemanticsLabel('Edit Apps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Netflix').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('App button 1'), findsOneWidget);
    await tester.tap(find.text('Disney+'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Disney+'), findsWidgets);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Reset to default'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Reset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await layout.read(), RemoteLayout.defaults);
    expect((await shortcuts.read()).first.appId, 'netflix');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Arrange remote'), findsNothing);
    expect(find.text('Roku'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });

  testWidgets('arrange preview follows hide, and Move up/down reorders', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final layout = MemoryLayoutStore();
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
    await tester.longPress(find.byType(HorizonPad));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(KeyRocker), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Hide Play controls'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(KeyRocker), findsNothing);

    Map<CustomSemanticsAction, VoidCallback> actions(RemoteBlockId id) => tester
        .widget<Semantics>(find.byKey(ValueKey('arrange-$id')))
        .properties
        .customSemanticsActions!;
    CustomSemanticsAction named(RemoteBlockId id, String label) =>
        actions(id).keys.firstWhere((a) => a.label == label);

    expect(actions(RemoteBlockId.powerRow).keys.map((a) => a.label), [
      'Move down',
    ]);
    actions(RemoteBlockId.powerRow)[named(
      RemoteBlockId.powerRow,
      'Move down',
    )]!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await layout.read()).blocks.take(2), [
      RemoteBlockId.shortcuts,
      RemoteBlockId.powerRow,
    ]);
    actions(RemoteBlockId.powerRow)[named(
      RemoteBlockId.powerRow,
      'Move up',
    )]!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await layout.read()).blocks.first, RemoteBlockId.powerRow);
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

    expect(
      await layout.read(),
      isA<RemoteLayout>().having(
        (value) => value.blocks,
        'blocks',
        isNot(contains(RemoteBlockId.pad)),
      ),
    );
    expect(find.text('Arrange remote'), findsNothing);
    expect(find.bySemanticsLabel('Arrange remote'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Arrange remote'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Arrange remote'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.bySemanticsLabel('Show D-pad'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Show D-pad'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await layout.read()).blocks, contains(RemoteBlockId.pad));
    expect(find.bySemanticsLabel('Show D-pad'), findsNothing);
  });

  Future<Completer<List<FarlyDevice>>> pumpHome(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    final scan = Completer<List<FarlyDevice>>();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: FarlyApp(
          readNetwork: _testNetwork,
          store: MemoryDeviceStore([
            const FarlyDevice(
              id: 'lg@192.168.1.20',
              name: 'Den',
              kind: DeviceKind.screen,
              brand: DeviceBrand.lg,
              host: '192.168.1.20',
              networkKeys: ['ssid:Test'],
              clientKey: 'k',
            ),
          ]),
          scanDevices: () => scan.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scan;
  }

  testWidgets('result shows brand and paired tags, no menu badge', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.textContaining('LG · Paired before'), findsOneWidget);
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('scan rings animate only while scanning', (tester) async {
    final scan = await pumpHome(tester);
    await tester.tap(find.text('Scan the room'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byKey(const Key('scan-progress')), findsOneWidget);
    scan.complete(const []);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const Key('scan-progress')), findsNothing);
  });

  testWidgets('reduced motion keeps the scan rings still', (tester) async {
    final scan = await pumpHome(tester, reduceMotion: true);
    await tester.tap(find.text('Scan the room'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Listening'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const Key('scan-progress')), findsNothing);
    scan.complete(const []);
    await tester.pump(const Duration(seconds: 3)); // first-scan retry delay
    await tester.pumpAndSettle();
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
