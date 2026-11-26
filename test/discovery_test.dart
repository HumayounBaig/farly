import 'dart:typed_data';

import 'package:farly/discovery/broadlink_hello.dart';
import 'package:farly/discovery/classifier.dart';
import 'package:farly/discovery/ssdp.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/state/device_merge.dart';
import 'package:farly/widgets/tv_maker_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ssdp LOCATION host must match the sender', () {
    expect(locationMatchesSender('192.168.1.23', '192.168.1.23'), isTrue);
    expect(locationMatchesSender('10.0.0.5', '192.168.1.23'), isFalse);
    expect(locationMatchesSender(null, '192.168.1.23'), isFalse);
  });

  test('ssdp parser reads roku headers', () {
    const raw =
        'HTTP/1.1 200 OK\r\n'
        'ST: roku:ecp\r\n'
        'LOCATION: http://192.168.1.23:8060/\r\n'
        'SERVER: Roku/9.2.0 UPnP/1.0\r\n'
        'USN: uuid:roku:ecp:YN00\r\n'
        '\r\n';
    final message = parseSsdp(raw);
    expect(message?.searchTarget, 'roku:ecp');
    final device = classifySsdp(message!);
    expect(device?.brand, DeviceBrand.roku);
    expect(device?.host, '192.168.1.23');
    expect(device?.port, 8060);
  });

  test('ssdp classifier separates lg, samsung, and sony', () {
    final lg = classifySsdp(
      parseSsdp(
        'HTTP/1.1 200 OK\nST: urn:lge-com:service:webos-second-screen:1\n'
        'LOCATION: http://192.168.1.40:1714/\nSERVER: LGE WebOS\n',
      )!,
    );
    final samsung = classifySsdp(
      parseSsdp(
        'HTTP/1.1 200 OK\nST: urn:samsung.com:device:RemoteControlReceiver:1\n'
        'LOCATION: http://192.168.1.50:7676/smp\nSERVER: Samsung\n',
      )!,
    );
    final sony = classifySsdp(
      parseSsdp(
        'HTTP/1.1 200 OK\nLOCATION: http://192.168.1.60:52323/dmr.xml\n'
        'SERVER: Sony-BRAVIA\nST: urn:schemas-upnp-org:device:MediaRenderer:1\n',
      )!,
    );
    expect(lg?.brand, DeviceBrand.lg);
    expect(samsung?.brand, DeviceBrand.samsung);
    expect(sony?.brand, DeviceBrand.sony);
    expect(sony?.descriptionUrl, contains('dmr.xml'));
  });

  test('mdns keeps apple tv and skips other airplay devices', () {
    final apple = classifyService(
      type: '_airplay._tcp',
      name: 'Living Room',
      host: '192.168.1.8',
      port: 7000,
      attributes: {'model': 'AppleTV11,1'},
    );
    final speaker = classifyService(
      type: '_airplay._tcp',
      name: 'Kitchen',
      host: '192.168.1.9',
      port: 7000,
      attributes: {'model': 'AudioAccessory'},
    );
    final android = classifyService(
      type: '_androidtvremote2._tcp',
      name: 'Frame',
      host: '192.168.1.10',
      port: 6466,
      attributes: const {},
    );
    expect(apple?.brand, DeviceBrand.appleTv);
    expect(speaker, isNull);
    expect(android?.brand, DeviceBrand.androidTv);
    expect(android?.port, 6466);
  });

  test('xml tag decode and ipv4 check', () {
    expect(
      xmlTag('<friendlyName>Living &amp; Room</friendlyName>', 'friendlyName'),
      'Living & Room',
    );
    expect(isIpv4Address('192.168.0.2'), isTrue);
    expect(isIpv4Address('192.168.0'), isFalse);
    expect(isIpv4Address('10.0.0.256'), isFalse);
  });

  test('broadlink hello checksum and response parse', () {
    final packet = buildBroadlinkHello(
      localIp: '192.168.1.5',
      localPort: 40000,
      now: DateTime.utc(2026, 10, 7, 12),
    );
    expect(packet.length, 0x30);
    expect(packet[0x26], 6);
    var checksum = 0xBEAF;
    final cleared = packet.toList();
    cleared[0x20] = 0;
    cleared[0x21] = 0;
    for (final byte in cleared) {
      checksum = (checksum + byte) & 0xFFFF;
    }
    expect(packet[0x20], checksum & 0xff);
    expect(packet[0x21], (checksum >> 8) & 0xff);

    final response = List<int>.filled(0x80, 0);
    response[0x34] = 0x12;
    response[0x35] = 0x27;
    response.setRange(0x40, 0x43, 'Hub'.codeUnits);
    final hub = parseBroadlinkHello(Uint8List.fromList(response));
    expect(hub?.name, 'Hub');
    expect(hub?.deviceType, 0x2712);
  });

  test('merge keeps a saved token and a custom name', () {
    const saved = FarlyDevice(
      id: 'samsung@192.168.1.4',
      name: 'Bedroom',
      kind: DeviceKind.screen,
      brand: DeviceBrand.samsung,
      host: '192.168.1.4',
      token: 'saved-token',
    );
    const found = FarlyDevice(
      id: 'samsung@192.168.1.4',
      name: 'Samsung',
      kind: DeviceKind.screen,
      brand: DeviceBrand.samsung,
      host: '192.168.1.4',
    );
    final seenAt = DateTime.utc(2026, 10, 7);
    final merged = mergeDevices(saved: [saved], found: [found], seenAt: seenAt);
    expect(merged.single.token, 'saved-token');
    expect(merged.single.name, 'Bedroom');
    expect(merged.single.lastSeen, seenAt);
  });

  test('a TV that keeps its uid remembers old addresses after a move', () {
    const saved = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'TCL C6K',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
      port: 6466,
      token: 'cert',
      clientKey: 'key',
      uid: 'castid1234567890abcdef1234567890',
    );
    final merged = mergeDevices(
      saved: [saved],
      found: [
        const FarlyDevice(
          id: 'androidTv@192.168.1.57',
          name: 'TCL C6K',
          kind: DeviceKind.screen,
          brand: DeviceBrand.androidTv,
          host: '192.168.1.57',
          port: 6466,
          uid: 'castid1234567890abcdef1234567890',
        ),
      ],
      seenAt: DateTime.utc(2026, 11, 10),
    );
    expect(merged, hasLength(1));
    expect(merged.single.host, '192.168.1.57');
    expect(merged.single.token, 'cert');
    expect(merged.single.clientKey, 'key');
    expect(
      merged.single.candidateHosts,
      containsAll(['192.168.1.57', '192.168.1.30']),
    );
  });

  test(
    'a locked name and icon survive a scan with a better announced name',
    () {
      const saved = FarlyDevice(
        id: 'roku@192.168.1.20',
        name: 'Lounge',
        kind: DeviceKind.screen,
        brand: DeviceBrand.roku,
        host: '192.168.1.20',
        icon: 'emoji:sofa',
        nameLocked: true,
      );
      const found = FarlyDevice(
        id: 'roku@192.168.1.20',
        name: 'Roku Ultra',
        kind: DeviceKind.screen,
        brand: DeviceBrand.roku,
        host: '192.168.1.20',
      );
      final merged = mergeDevices(
        saved: [saved],
        found: [found],
        seenAt: DateTime.utc(2026, 11, 10),
      );
      expect(merged.single.name, 'Lounge');
      expect(merged.single.icon, 'emoji:sofa');
      expect(merged.single.nameLocked, isTrue);
    },
  );

  group('rescans keep one entry per TV', () {
    const paired = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'TCL C6K',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
      port: 6466,
      token: 'cert',
      clientKey: 'key',
      uid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    );
    final seenAt = DateTime.utc(2026, 10, 15);

    test('a vaguer answer at the same address does not add a copy', () {
      for (final vaguer in [
        const FarlyDevice(
          id: 'chromecast@192.168.1.30',
          name: 'TCL C6K',
          kind: DeviceKind.screen,
          brand: DeviceBrand.chromecast,
          host: '192.168.1.30',
        ),
        const FarlyDevice(
          id: 'unknown@192.168.1.30',
          name: 'Device',
          kind: DeviceKind.screen,
          brand: DeviceBrand.unknown,
          host: '192.168.1.30',
        ),
      ]) {
        final merged = mergeDevices(
          saved: [paired],
          found: [vaguer],
          seenAt: seenAt,
        );
        expect(merged, hasLength(1));
        expect(merged.single.id, paired.id);
        expect(merged.single.brand, DeviceBrand.androidTv);
        expect(merged.single.name, 'TCL C6K');
        expect(merged.single.token, 'cert');
        expect(merged.single.lastSeen, seenAt);
      }
    });

    test('a TV on a new address replaces its old entry', () {
      const moved = FarlyDevice(
        id: 'androidTv@192.168.1.44',
        name: 'TCL C6K',
        kind: DeviceKind.screen,
        brand: DeviceBrand.androidTv,
        host: '192.168.1.44',
        port: 6466,
        uid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
      );
      final byUid = mergeDevices(
        saved: [paired],
        found: [moved],
        seenAt: seenAt,
      );
      expect(byUid, hasLength(1));
      expect(byUid.single.host, '192.168.1.44');
      expect(byUid.single.clientKey, 'key');

      const movedWithoutUid = FarlyDevice(
        id: 'androidTv@192.168.1.44',
        name: 'TCL C6K',
        kind: DeviceKind.screen,
        brand: DeviceBrand.androidTv,
        host: '192.168.1.44',
        port: 6466,
      );
      final byName = mergeDevices(
        saved: [paired],
        found: [movedWithoutUid],
        seenAt: seenAt,
      );
      expect(byName, hasLength(1));
      expect(byName.single.host, '192.168.1.44');
    });

    test('two TVs with the same name both stay when both answer', () {
      const other = FarlyDevice(
        id: 'androidTv@192.168.1.31',
        name: 'TCL C6K',
        kind: DeviceKind.screen,
        brand: DeviceBrand.androidTv,
        host: '192.168.1.31',
        port: 6466,
      );
      final merged = mergeDevices(
        saved: [paired],
        found: [
          paired.copyWith(uid: 'a1b2c3d4e5f60718293a4b5c6d7e8f90'),
          other,
        ],
        seenAt: seenAt,
      );
      expect(merged, hasLength(2));
    });

    test('copies saved by an earlier build collapse into one', () {
      final copies = [
        const FarlyDevice(
          id: 'chromecast@192.168.1.30',
          name: 'TCL C6K',
          kind: DeviceKind.screen,
          brand: DeviceBrand.chromecast,
          host: '192.168.1.30',
        ),
        paired.copyWith(lastSeen: seenAt),
        const FarlyDevice(
          id: 'unknown@192.168.1.30',
          name: 'Device',
          kind: DeviceKind.screen,
          brand: DeviceBrand.unknown,
          host: '192.168.1.30',
        ),
      ];
      final collapsed = collapseDevices(copies);
      expect(collapsed, hasLength(1));
      expect(collapsed.single.brand, DeviceBrand.androidTv);
      expect(collapsed.single.token, 'cert');
      expect(collapsed.single.name, 'TCL C6K');
    });
  });

  test('scan answers from one address share their name and identity', () {
    final byHost = <String, FarlyDevice>{};
    putBetterDevice(
      byHost,
      const FarlyDevice(
        id: 'unknown@192.168.1.30',
        name: 'Device',
        kind: DeviceKind.screen,
        brand: DeviceBrand.unknown,
        host: '192.168.1.30',
        uid: 'abc',
      ),
    );
    putBetterDevice(
      byHost,
      const FarlyDevice(
        id: 'chromecast@192.168.1.30',
        name: 'TCL C6K',
        kind: DeviceKind.screen,
        brand: DeviceBrand.chromecast,
        host: '192.168.1.30',
      ),
    );
    final device = byHost['192.168.1.30']!;
    expect(device.brand, DeviceBrand.chromecast);
    expect(device.name, 'TCL C6K');
    expect(device.uid, 'abc');
  });

  test('repeated scans of a saved TV stay one entry, even after it moves', () {
    const saved = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'Android TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
      port: 6466,
      token: 'cert',
      clientKey: 'key',
    );
    var list = [saved];
    for (final host in ['192.168.1.30', '192.168.1.30', '192.168.1.57']) {
      list = mergeDevices(
        saved: list,
        found: [
          FarlyDevice(
            id: 'androidTv@$host',
            name: 'Android TV',
            kind: DeviceKind.screen,
            brand: DeviceBrand.androidTv,
            host: host,
            port: 6466,
          ),
        ],
        seenAt: DateTime.utc(2026, 10, 16),
      );
      expect(list, hasLength(1));
    }
    expect(list.single.host, '192.168.1.57');
    // A guessed match never hands pairing to the new address.
    expect(list.single.token, isNull);
    expect(list.single.clientKey, isNull);
  });

  test('a different generic TV never inherits a silent TV\'s pairing', () {
    const saved = FarlyDevice(
      id: 'androidTv@192.168.1.30',
      name: 'Android TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.30',
      token: 'cert',
      clientKey: 'key',
      uid: 'aaaa',
    );
    const other = FarlyDevice(
      id: 'androidTv@192.168.1.60',
      name: 'Android TV',
      kind: DeviceKind.screen,
      brand: DeviceBrand.androidTv,
      host: '192.168.1.60',
    );
    final differentUid = mergeDevices(
      saved: [saved],
      found: [other.copyWith(uid: 'bbbb')],
      seenAt: DateTime.utc(2026, 10, 16),
    );
    expect(differentUid, hasLength(2));

    final noUid = mergeDevices(
      saved: [saved.copyWith(clearToken: true, clearClientKey: true)],
      found: [other],
      seenAt: DateTime.utc(2026, 10, 16),
    );
    expect(noUid.single.clientKey, isNull);

    final unsure = mergeDevices(
      saved: [
        const FarlyDevice(
          id: 'androidTv@192.168.1.30',
          name: 'Android TV',
          kind: DeviceKind.screen,
          brand: DeviceBrand.androidTv,
          host: '192.168.1.30',
          token: 'cert',
          clientKey: 'key',
        ),
      ],
      found: [
        other,
        const FarlyDevice(
          id: 'androidTv@192.168.1.61',
          name: 'Android TV',
          kind: DeviceKind.screen,
          brand: DeviceBrand.androidTv,
          host: '192.168.1.61',
        ),
      ],
      seenAt: DateTime.utc(2026, 10, 16),
    );
    expect(unsure, hasLength(3));
    expect(unsure.where((d) => d.clientKey != null), hasLength(1));
    expect(unsure.firstWhere((d) => d.clientKey != null).host, '192.168.1.30');
  });

  test('TV maker comes from the protocol or the announced name', () {
    FarlyDevice tv(DeviceBrand brand, String name) =>
        FarlyDevice(id: 'x', name: name, kind: DeviceKind.screen, brand: brand);
    expect(tvMakerOf(tv(DeviceBrand.lg, 'LG'))?.label, 'LG');
    expect(tvMakerOf(tv(DeviceBrand.samsung, 'Den'))?.label, 'SAMSUNG');
    expect(tvMakerOf(tv(DeviceBrand.androidTv, 'TCL C6K'))?.label, 'TCL');
    expect(tvMakerOf(tv(DeviceBrand.androidTv, 'BRAVIA 4K'))?.label, 'SONY');
    expect(tvMakerOf(tv(DeviceBrand.androidTv, 'Living room')), isNull);
    expect(tvMakerOf(tv(DeviceBrand.androidTv, 'Fantcl')), isNull);
    for (final name in ['Mi TV', 'MiTV 4S', 'Xiaomi TV']) {
      expect(tvMakerOf(tv(DeviceBrand.androidTv, name))?.label, 'MI');
    }
    expect(tvMakerOf(tv(DeviceBrand.androidTv, 'Family TV')), isNull);
    expect(
      tvMakerOf(
        const FarlyDevice(
          id: 'y',
          name: 'LG',
          kind: DeviceKind.climate,
          brand: DeviceBrand.otherAc,
        ),
      ),
      isNull,
    );
  });

  test('USN and Cast ids normalize to one identity', () {
    expect(
      uidFromUsn(
        'uuid:a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f90::urn:dial-multiscreen-org:service:dial:1',
      ),
      'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    );
    expect(uidFromUsn('uuid:roku:ecp:X00800ABCDE'), 'roku:ecp:x00800abcde');
    expect(
      normalizeUid('A1B2C3D4E5F60718293A4B5C6D7E8F90'),
      'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    );
  });
}
