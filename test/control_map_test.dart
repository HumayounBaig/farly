import 'dart:typed_data';

import 'package:farly/control/atv_wire.dart';
import 'package:farly/control/lg_registration.dart';
import 'package:farly/control/roku_session.dart';
import 'package:farly/control/samsung_keys.dart';
import 'package:farly/models/remote_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roku and samsung key maps', () {
    expect(rokuKey(RemoteAction.volumeUp), 'VolumeUp');
    expect(rokuKey(RemoteAction.input), isNull);
    expect(samsungKey(RemoteAction.power), 'KEY_POWER');
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

  test('typed text payloads for roku, samsung, and android tv', () {
    expect(rokuLitPath('a'), 'Lit_a');
    expect(rokuLitPath(' '), 'Lit_%20');
    final samsung = samsungTextPayload('secret');
    expect(samsung['params']['Cmd'], 'WriteString');
    expect(samsung['params']['DataOfCmd'], 'secret');
    expect(samsung['params']['TypeOfRemote'], 'SendInputString');

    final frame = decodeProto(
      atvImeBatchEdit(imeCounter: 3, fieldCounter: 7, text: 'hi'),
    ).message(21)!;
    expect(frame.integer(1), 3);
    expect(frame.integer(2), 7);
    final edit = frame.message(3)!;
    expect(edit.integer(1), 1);
    final ime = edit.message(2)!;
    expect(ime.integer(1), 2);
    expect(ime.integer(2), 2);
    expect(String.fromCharCodes(ime[3]!.first as Uint8List), 'hi');

    final inject =
        (ProtoWriter()..message(
              20,
              ProtoWriter()
                ..message(1, ProtoWriter()..varint(1, 9))
                ..message(2, ProtoWriter()..varint(1, 4)),
            ))
            .toBytes();
    final event = parseAtvRemote(inject);
    expect(event, isA<AtvImeFocusEvent>());
    expect((event as AtvImeFocusEvent).imeCounter, 9);
    expect(event.fieldCounter, 4);
    expect(atvFeatures & 4, 4);
  });

  test('lg registration keeps the client key beside the signed manifest', () {
    final fresh = lgRegistration();
    final saved = lgRegistration(clientKey: 'client-key');
    expect(fresh['payload']['client-key'], isNull);
    expect(saved['payload']['client-key'], 'client-key');
    expect(lgPointerButton(RemoteAction.home), 'HOME');
    expect(lgPointerMessage('UP'), 'type:button\nname:UP\n\n');
    expect(
      lgRequest('cmd_1', 'ssap://audio/volumeUp')['uri'],
      'ssap://audio/volumeUp',
    );
  });
}
