import 'dart:io';
import 'dart:typed_data';

import 'package:farly/control/android_tv_session.dart';
import 'package:farly/control/atv_identity.dart';
import 'package:farly/control/atv_wire.dart';
import 'package:farly/control/remote_session.dart';
import 'package:farly/discovery/classifier.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/models/remote_action.dart';
import 'package:farly/state/device_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;

final _client = createAtvIdentity(bits: 1024);
final _server = createAtvIdentity(bits: 1024);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  test('every pad button has an Android TV key code', () {
    for (final action in RemoteAction.values) {
      expect(atvKeyCode(action), isNotNull, reason: action.name);
    }
    expect(atvKeyCode(RemoteAction.up), 19);
    expect(atvKeyCode(RemoteAction.select), 23);
    expect(atvKeyCode(RemoteAction.back), 4);
    expect(atvKeyCode(RemoteAction.home), 3);
    expect(atvKeyCode(RemoteAction.power), 26);
    expect(atvKeyCode(RemoteAction.mute), 164);
    expect(atvKeyCode(RemoteAction.input), 178);
  });

  test('wire messages encode the fields the TV reads', () {
    final request = decodeProto(atvPairingRequest('Farly'));
    expect(request.integer(1), 2);
    expect(request.integer(2), 200);
    final body = request.message(10)!;
    expect(String.fromCharCodes(body[1]!.first as Uint8List), 'atvremote');
    expect(String.fromCharCodes(body[2]!.first as Uint8List), 'Farly');

    final option = decodeProto(atvPairingOption()).message(20)!;
    expect(option.message(1)!.integer(1), 3);
    expect(option.message(1)!.integer(2), 6);
    expect(option.integer(3), 1);

    final key = decodeProto(atvKeyInject(23)).message(10)!;
    expect(key.integer(1), 23);
    expect(key.integer(2), 3);

    final ping = (ProtoWriter()..message(8, ProtoWriter()..varint(1, 300)))
        .toBytes();
    expect(parseAtvRemote(ping), isA<AtvPingEvent>());
    expect((parseAtvRemote(ping) as AtvPingEvent).value, 300);
    expect(decodeProto(atvPingResponse(300)).message(9)!.integer(1), 300);
  });

  test('frame reader rebuilds messages split across reads', () {
    final reader = AtvFrameReader();
    final long = Uint8List(200)..fillRange(0, 200, 7);
    final stream = [
      ...atvFrame(Uint8List.fromList([1, 2])),
      ...atvFrame(long),
    ];
    expect(reader.add(stream.sublist(0, 2)), isEmpty);
    final first = reader.add(stream.sublist(2, 5));
    expect(first.single, [1, 2]);
    final rest = reader.add(stream.sublist(5));
    expect(rest.single.length, 200);
  });

  test('identity is a parseable RSA certificate', () {
    final numbers = rsaPublicNumbers(_client.certificateDer)!;
    expect(numbers.exponent, [1, 0, 1]);
    expect(numbers.modulus.length, 128);
    expect(numbers.modulus.first, isNot(0));
    expect(
      _client.privateKeyPem,
      startsWith('-----BEGIN RSA PRIVATE KEY-----'),
    );
  });

  test('pairing secret hashes both keys and the code nonce', () {
    final client = rsaPublicNumbers(_client.certificateDer)!;
    final server = rsaPublicNumbers(_server.certificateDer)!;
    final digest = SHA256Digest();
    for (final part in [
      client.modulus,
      client.exponent,
      server.modulus,
      server.exponent,
      Uint8List.fromList([0xAB, 0xCD]),
    ]) {
      digest.update(part, 0, part.length);
    }
    final expected = Uint8List(32);
    digest.doFinal(expected, 0);

    final code = '${_hex([expected[0]])}abcd';
    final secret = atvPairingSecret(
      clientCertificateDer: _client.certificateDer,
      serverCertificateDer: _server.certificateDer,
      code: code,
    );
    expect(secret, expected);

    final wrongCheck = '${_hex([(expected[0] + 1) & 0xff])}ABCD';
    expect(
      atvPairingSecret(
        clientCertificateDer: _client.certificateDer,
        serverCertificateDer: _server.certificateDer,
        code: wrongCheck,
      ),
      isNull,
    );
    expect(normalizeAtvCode(' a1b2c3 '), 'A1B2C3');
    expect(normalizeAtvCode('A1B2C'), isNull);
    expect(normalizeAtvCode('G1B2C3'), isNull);
  });

  test('cast TVs become Android TV, speakers stay Cast', () {
    final tcl = classifyService(
      type: '_googlecast._tcp',
      name: 'TCL-Smart-TV-0123456789abcdef0123456789abcdef',
      host: '192.168.1.30',
      port: 8009,
      attributes: {'md': 'Smart TV', 'fn': 'Living Room TV'},
    );
    final speaker = classifyService(
      type: '_googlecast._tcp',
      name: 'Google-Nest-Mini-0123456789abcdef0123456789abcdef',
      host: '192.168.1.31',
      port: 8009,
      attributes: {'md': 'Google Nest Mini'},
    );
    expect(tcl?.brand, DeviceBrand.androidTv);
    expect(tcl?.name, 'Living Room TV');
    expect(tcl?.port, 6466);
    expect(speaker?.brand, DeviceBrand.chromecast);
    expect(speaker?.name, 'Google-Nest-Mini');
    expect(DeviceBrand.androidTv.commandsReady, isTrue);

    final promoted = asAndroidTv(speaker!);
    expect(promoted.id, 'androidTv@192.168.1.31');
    expect(promoted.port, 6466);
  });

  test('a rescan replaces a saved Cast entry and keeps its pairing', () {
    const saved = FarlyDevice(
      id: 'chromecast@192.168.1.30',
      name: 'Den',
      kind: DeviceKind.screen,
      brand: DeviceBrand.chromecast,
      host: '192.168.1.30',
      token: 'cert',
      clientKey: 'key',
    );
    const found = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'Android TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
      port: 6466,
    );
    final merged = mergeDevices(
      saved: [saved],
      found: [found],
      seenAt: DateTime.utc(2026, 10, 8),
    );
    expect(merged.single.id, 'androidTv@192.168.1.30');
    expect(merged.single.name, 'Den');
    expect(merged.single.token, 'cert');
    expect(merged.single.clientKey, 'key');
  });

  test('pairs with a TV, sends keys, and reconnects without a code', () async {
    final tv = await _FakeTv.start();
    addTearDown(tv.stop);

    FarlyDevice? stored;
    final session = AndroidTvSession(
      device: const FarlyDevice(
        id: 'androidTv@127.0.0.1',
        name: 'TCL',
        kind: DeviceKind.screen,
        brand: DeviceBrand.androidTv,
        host: '127.0.0.1',
      ),
      onCredentials: (device) => stored = device,
      pairingPort: tv.pairingPort,
      remotePort: tv.remotePort,
      identities: () async => _client,
    );
    final phases = <SessionPhase>[];
    session.updates.listen((update) => phases.add(update.phase));

    await session.open();
    await pumpEventQueue();
    expect(phases.last, SessionPhase.pairing);

    final mismatch = await session.submitCode(tv.wrongCode);
    expect(mismatch.ok, isFalse);
    expect(mismatch.detail, contains('does not match'));

    final paired = await session.submitCode(tv.code.toLowerCase());
    expect(paired.ok, isTrue);
    await pumpEventQueue();
    expect(phases.last, SessionPhase.ready);
    expect(stored?.token, _client.certificatePem);
    expect(stored?.clientKey, _client.privateKeyPem);

    expect((await session.send(RemoteAction.up)).ok, isTrue);
    expect((await session.send(RemoteAction.volumeUp)).ok, isTrue);
    expect((await session.launch(AndroidTvSession.apps.first)).ok, isTrue);
    await tv.waitForKeys(2);
    expect(tv.keys, [19, 24]);
    expect(tv.pingAnswered, isTrue);
    expect(tv.activeReply, 622 & atvFeatures);
    expect(tv.appLinks, ['https://www.netflix.com/title']);
    await session.close();

    final again = AndroidTvSession(
      device: stored!,
      pairingPort: tv.pairingPort,
      remotePort: tv.remotePort,
      identities: () async => throw StateError('should not pair again'),
    );
    final againPhases = <SessionPhase>[];
    again.updates.listen((update) => againPhases.add(update.phase));
    await again.open();
    await pumpEventQueue();
    expect(againPhases.last, SessionPhase.ready);
    expect(againPhases, isNot(contains(SessionPhase.pairing)));
    expect((await again.send(RemoteAction.home)).ok, isTrue);
    await tv.waitForKeys(3);
    expect(tv.keys.last, 3);
    await again.close();
  });

  test('a TV that does not answer fails with a clear message', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final session = AndroidTvSession(
      device: const FarlyDevice(
        id: 'androidTv@127.0.0.1',
        name: 'TCL',
        kind: DeviceKind.screen,
        brand: DeviceBrand.androidTv,
        host: '127.0.0.1',
      ),
      pairingPort: port,
      remotePort: port,
      identities: () async => _client,
      timeout: const Duration(seconds: 1),
    );
    final updates = <SessionUpdate>[];
    session.updates.listen(updates.add);
    await session.open();
    await pumpEventQueue();
    expect(updates.last.phase, SessionPhase.failed);
    expect(updates.last.detail, contains('did not answer'));
    expect((await session.send(RemoteAction.up)).ok, isFalse);
    await session.close();
  });
}

/// A loopback stand-in for a Google TV: pairing on one port, keys on another.
class _FakeTv {
  _FakeTv(this._pairing, this._remote);

  final SecureServerSocket _pairing;
  final SecureServerSocket _remote;
  final keys = <int>[];
  final appLinks = <String>[];
  final _trusted = <String>{};
  var pingAnswered = false;
  int? activeReply;
  late String code;
  late String wrongCode;

  int get pairingPort => _pairing.port;
  int get remotePort => _remote.port;

  static Future<_FakeTv> start() async {
    SecurityContext context() => SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(_server.certificatePem.codeUnits)
      ..usePrivateKeyBytes(_server.privateKeyPem.codeUnits)
      ..setTrustedCertificatesBytes(_client.certificatePem.codeUnits);
    final tv = _FakeTv(
      await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context(),
        requestClientCertificate: true,
      ),
      await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context(),
        requestClientCertificate: true,
      ),
    );
    tv._pairing.listen(tv._pair);
    tv._remote.listen(tv._control);
    return tv;
  }

  void _pair(SecureSocket socket) {
    final client = socket.peerCertificate!.der;
    final nonce = [0x5E, 0x0A];
    final hash = _hash(client, nonce);
    code = _hex([hash[0], ...nonce]);
    wrongCode = _hex([(hash[0] + 1) & 0xff, ...nonce]);
    final reader = AtvFrameReader();
    socket.listen((chunk) {
      for (final frame in reader.add(chunk)) {
        final fields = decodeProto(frame);
        final reply = ProtoWriter()
          ..varint(1, 2)
          ..varint(2, 200);
        if (fields.has(10)) {
          reply.message(11, ProtoWriter()..string(1, 'TCL C6K'));
        } else if (fields.has(20)) {
          reply.message(20, ProtoWriter()..varint(3, 1));
        } else if (fields.has(30)) {
          reply.message(31, ProtoWriter());
        } else if (fields.has(40)) {
          final sent = fields.message(40)![1]!.first as Uint8List;
          if (_hex(sent) == _hex(hash)) {
            _trusted.add(_hex(client));
            reply.message(41, ProtoWriter()..bytes(1, hash));
          } else {
            socket.add(
              atvFrame(
                (ProtoWriter()
                      ..varint(1, 2)
                      ..varint(2, 402))
                    .toBytes(),
              ),
            );
            continue;
          }
        }
        socket.add(atvFrame(reply.toBytes()));
      }
    });
  }

  Uint8List _hash(Uint8List clientDer, List<int> nonce) {
    final client = rsaPublicNumbers(clientDer)!;
    final server = rsaPublicNumbers(_server.certificateDer)!;
    final digest = SHA256Digest();
    for (final part in [
      client.modulus,
      client.exponent,
      server.modulus,
      server.exponent,
      Uint8List.fromList(nonce),
    ]) {
      digest.update(part, 0, part.length);
    }
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  void _control(SecureSocket socket) {
    final client = socket.peerCertificate?.der;
    if (client == null || !_trusted.contains(_hex(client))) {
      socket.destroy();
      return;
    }
    socket.add(
      atvFrame(
        (ProtoWriter()..message(1, ProtoWriter()..varint(1, 622))).toBytes(),
      ),
    );
    final reader = AtvFrameReader();
    socket.listen((chunk) {
      for (final frame in reader.add(chunk)) {
        final fields = decodeProto(frame);
        if (fields.has(1)) {
          socket.add(
            atvFrame(
              (ProtoWriter()..message(2, ProtoWriter()..varint(1, 622)))
                  .toBytes(),
            ),
          );
          socket.add(
            atvFrame(
              (ProtoWriter()..message(8, ProtoWriter()..varint(1, 41)))
                  .toBytes(),
            ),
          );
          socket.add(
            atvFrame(
              (ProtoWriter()..message(40, ProtoWriter()..varint(1, 1)))
                  .toBytes(),
            ),
          );
        } else if (fields.has(2)) {
          activeReply = fields.message(2)!.integer(1);
        } else if (fields.has(9)) {
          pingAnswered = fields.message(9)!.integer(1) == 41;
        } else if (fields.has(10)) {
          keys.add(fields.message(10)!.integer(1)!);
        } else if (fields.has(90)) {
          appLinks.add(
            String.fromCharCodes(fields.message(90)![1]!.first as Uint8List),
          );
        }
      }
    });
  }

  Future<void> waitForKeys(int count) async {
    for (var i = 0; i < 100 && keys.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> stop() async {
    await _pairing.close();
    await _remote.close();
  }
}
