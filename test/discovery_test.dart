import 'dart:typed_data';

import 'package:farly/discovery/broadlink_hello.dart';
import 'package:farly/discovery/classifier.dart';
import 'package:farly/discovery/ssdp.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/state/device_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ssdp parser reads roku headers', () {
    const raw = 'HTTP/1.1 200 OK\r\n'
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
    expect(xmlTag('<friendlyName>Living &amp; Room</friendlyName>', 'friendlyName'), 'Living & Room');
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
}
