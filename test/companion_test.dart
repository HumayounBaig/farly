import 'package:farly/control/remote_session.dart';
import 'package:farly/discovery/network_context.dart';
import 'package:farly/mac/companion_app.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/remote_action.dart';
import 'package:farly/storage/device_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<NetworkFingerprint?> _testNetwork() async => const NetworkFingerprint(
  key: 'ssid:Home',
  label: 'Home',
  ssidKey: 'ssid:Home',
  subnetKey: 'subnet:192.168.1',
);

void main() {
  testWidgets('companion lists a saved TV and opens the pad', (tester) async {
    await tester.pumpWidget(
      FarlyCompanionApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Living room',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
            port: 8060,
            networkKeys: ['ssid:Home'],
          ),
        ]),
        scanDevices: () async => const [],
        sessions: (device, onCredentials) => NotedSession(
          phase: SessionPhase.ready,
          detail: 'Ready',
          preview: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Living room'), findsOneWidget);
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Direction pad'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Type on the TV'), findsOneWidget);
  });

  testWidgets('companion shows empty guidance when no TVs are saved', (
    tester,
  ) async {
    await tester.pumpWidget(
      FarlyCompanionApp(
        readNetwork: _testNetwork,
        store: MemoryDeviceStore(),
        scanDevices: () async => const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('phone app does not need to be open'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}
