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
    final uri = samsungSocketUri(host: '192.168.1.4', secure: true, token: 'abc');
    expect(uri.scheme, 'wss');
    expect(uri.port, 8002);
    expect(uri.queryParameters['token'], 'abc');
    expect(uri.queryParameters['name'], isNotEmpty);
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
