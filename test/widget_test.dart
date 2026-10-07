import 'package:farly/app.dart';
import 'package:farly/control/remote_session.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/storage/device_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scan notice and preview pad', (tester) async {
    await tester.pumpWidget(
      FarlyApp(
        store: MemoryDeviceStore([
          const FarlyDevice(
            id: 'roku@192.168.1.20',
            name: 'Living room',
            kind: DeviceKind.screen,
            brand: DeviceBrand.roku,
            host: '192.168.1.20',
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
    expect(
      find.text(
        'Nothing answered. Use the same Wi-Fi as the TV, or add an address.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Preview the pad'));
    await tester.pumpAndSettle();
    expect(find.text('Preview. Nothing is connected.'), findsOneWidget);

    await tester.tap(find.text('Vol +'));
    await tester.pumpAndSettle();
    expect(find.text('Would send Volume up'), findsOneWidget);
  });

  testWidgets('address sheet rejects a bad address', (tester) async {
    await tester.pumpWidget(
      FarlyApp(
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
}
