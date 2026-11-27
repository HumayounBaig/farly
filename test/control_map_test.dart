import 'dart:typed_data';

import 'package:farly/control/atv_wire.dart';
import 'package:farly/control/lg_registration.dart';
import 'package:farly/control/roku_session.dart';
import 'package:farly/control/samsung_keys.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/menu_command.dart';
import 'package:farly/models/remote_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roku and samsung key maps', () {
    expect(rokuKey(RemoteAction.volumeUp), 'VolumeUp');
    expect(rokuKey(RemoteAction.menu), 'Info');
    expect(rokuMenuKey('search'), 'Search');
    expect(rokuKey(RemoteAction.input), isNull);
    expect(rokuKey(RemoteAction.brightnessUp), isNull);
    expect(samsungKey(RemoteAction.power), 'KEY_POWER');
    expect(samsungKey(RemoteAction.menu), 'KEY_MENU');
    expect(samsungMenuKey('tools'), 'KEY_TOOLS');
    expect(samsungKey(RemoteAction.brightnessUp), 'KEY_BRIGHTNESS_UP');
    expect(samsungKeyPayload('KEY_HOME')['method'], 'ms.remote.control');
    final uri = samsungSocketUri(
      host: '192.168.1.4',
      secure: true,
      token: 'abc',
    );
    expect(uri.scheme, 'wss');
    expect(uri.port, 8002);
    expect(uri.queryParameters['token'], 'abc');
    expect(uri.queryParameters['name'], isNotEmpty);
  });

  test('samsung per-character keys for text without an IME session', () {
    expect(samsungCharKey('a'), 'KEY_A');
    expect(samsungCharKey('Z'), 'KEY_Z');
    expect(samsungCharKey('7'), 'KEY_7');
    expect(samsungCharKey(' '), 'KEY_SPACE');
    expect(samsungCharKey('é'), isNull);
    expect(samsungCharKey('ab'), isNull);
  });

  test('typed text payloads for roku, samsung, and android tv', () {
    expect(rokuLitPath('a'), 'Lit_a');
    expect(rokuLitPath(' '), 'Lit_%20');
    final samsung = samsungTextPayload('secret');
    expect(samsung['params']['Cmd'], 'WriteString');
    expect(samsung['params']['DataOfCmd'], 'secret');
    expect(samsung['params']['TypeOfRemote'], 'SendInputString');

    final frame = decodeProto(
      atvImeBatchEdit(
        imeCounter: 3,
        fieldCounter: 7,
        text: 'hi',
        start: 0,
        end: 0,
      ),
    ).message(21)!;
    expect(frame.integer(1), 3);
    expect(frame.integer(2), 7);
    final edit = frame.message(3)!;
    expect(edit.integer(1), 1);
    final ime = edit.message(2)!;
    expect(ime.integer(1), 0);
    expect(ime.integer(2), 0);
    expect(String.fromCharCodes(ime[3]!.first as Uint8List), 'hi');
    expect(atvCharKeyCode('@'), 77);
    expect(atvCharKeyCode('a'), 29);

    final inject =
        (ProtoWriter()..message(
              20,
              ProtoWriter()
                ..message(1, ProtoWriter()..varint(1, 9))
                ..message(
                  2,
                  ProtoWriter()
                    ..varint(1, 4)
                    ..string(2, 'ab')
                    ..string(6, 'Email'),
                ),
            ))
            .toBytes();
    final event = parseAtvRemote(inject);
    expect(event, isA<AtvImeFocusEvent>());
    expect((event as AtvImeFocusEvent).imeCounter, 9);
    expect(event.fieldCounter, 4);
    expect(event.fieldValue, 'ab');
    expect(event.fieldLabel, 'Email');
    expect(event.hasFieldStatus, isTrue);
    expect(atvFeatures & 4, 4);
  });

  test('lg registration keeps the client key beside the signed manifest', () {
    final fresh = lgRegistration();
    final saved = lgRegistration(clientKey: 'client-key');
    expect(fresh['payload']['client-key'], isNull);
    expect(saved['payload']['client-key'], 'client-key');
    expect(lgPointerButton(RemoteAction.home), 'HOME');
    expect(lgPointerButton(RemoteAction.menu), 'MENU');
    expect(lgMenuButton('info'), 'INFO');
    expect(lgPointerButton(RemoteAction.input), isNull);
    expect(lgPointerMessage('UP'), 'type:button\nname:UP\n\n');
    expect(
      lgRequest('cmd_1', 'ssap://audio/volumeUp')['uri'],
      'ssap://audio/volumeUp',
    );
  });

  test('TCL Android TVs default Menu to Settings', () {
    const tcl = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'TCL C6K',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
    );
    const other = FarlyDevice(
      id: 'androidTv@192.168.1.31',
      name: 'Living room',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.31',
    );
    expect(MenuCommand.defaultIdFor(tcl), 'settings');
    expect(atvMenuKeyCode(MenuCommand.resolvedId(tcl)), 176);
    expect(MenuCommand.defaultIdFor(other), 'menu');
    expect(
      MenuCommand.resolvedId(tcl.copyWith(menuCommand: 'allApps')),
      'allApps',
    );
  });
}
