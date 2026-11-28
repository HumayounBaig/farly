import 'package:farly/discovery/classifier.dart';
import 'package:farly/discovery/device_info.dart';
import 'package:farly/models/farly_device.dart';
import 'package:farly/state/device_merge.dart';
import 'package:farly/sync/device_sync.dart';
import 'package:flutter_test/flutter_test.dart';

FarlyDevice tv(
  DeviceBrand brand,
  String host, {
  String? name,
  String? model,
  String? uid,
}) => FarlyDevice(
  id: FarlyDevice.idFor(brand, host),
  name: name ?? brand.label,
  kind: brand.kind,
  brand: brand,
  host: host,
  uid: uid,
  model: model,
);

void main() {
  final seen = DateTime(2026, 1, 1);

  group('parsers', () {
    test('roku device-info', () {
      const xml =
          '<device-info><user-device-name>Den TV</user-device-name>'
          '<friendly-model-name>Roku Ultra</friendly-model-name>'
          '<model-name>4800X</model-name><is-tv>false</is-tv></device-info>';
      final info = parseRokuInfo(xml)!;
      expect(info.name, 'Den TV');
      expect(info.model, 'Roku Ultra');
      expect(parseRokuInfo('<x/>'), isNull);
    });

    test('ssdp description prefers a real model number', () {
      const xml =
          '<root><device><friendlyName>[LG] webOS TV</friendlyName>'
          '<modelName>LG Smart TV</modelName>'
          '<modelNumber>OLED55C1PUB</modelNumber></device></root>';
      final info = parseSsdpDescription(xml)!;
      expect(info.name, '[LG] webOS TV');
      expect(info.model, 'OLED55C1PUB');
      const plain =
          '<root><friendlyName>TV</friendlyName><modelName>XR-55A80J</modelName></root>';
      expect(parseSsdpDescription(plain)!.model, 'XR-55A80J');
    });

    test('samsung api json', () {
      const json =
          '{"device":{"name":"[TV] Samsung 7","modelName":"UN55TU8000"}}';
      final info = parseSamsungInfo(json)!;
      expect(info.name, '[TV] Samsung 7');
      expect(info.model, 'UN55TU8000');
      expect(parseSamsungInfo('not json'), isNull);
      expect(parseSamsungInfo('{"device":3}'), isNull);
    });

    test('cast txt', () {
      final info = parseCastTxt({'fn': 'Bedroom', 'md': 'Chromecast Ultra'})!;
      expect(info.name, 'Bedroom');
      expect(info.model, 'Chromecast Ultra');
      final device = classifyService(
        type: '_googlecast._tcp',
        name: 'Bedroom-0123456789abcdef0123456789abcdef',
        host: '192.168.1.9',
        port: 8009,
        attributes: {'fn': 'Bedroom', 'md': 'Chromecast Ultra'},
      );
      expect(device?.model, 'Chromecast Ultra');
      expect(device?.name, 'Bedroom');
    });

    test('untrusted text is cleaned and capped', () {
      expect(cleanLabel('  a\u0000b\n\tc  '), 'a b c');
      expect(cleanLabel('x' * 100)!.length, 60);
      expect(cleanLabel('\u0001  '), isNull);
      final info = parseRokuInfo(
        '<user-device-name>Tv\u0007</user-device-name>',
      )!;
      expect(info.name, 'Tv');
    });

    test('private LAN hosts only', () {
      for (final ok in [
        '10.0.0.2',
        '192.168.1.5',
        '172.16.0.1',
        '172.31.9.9',
      ]) {
        expect(isPrivateIpv4(ok), isTrue, reason: ok);
      }
      for (final bad in ['8.8.8.8', '172.32.0.1', 'tv.local', '192.169.1.1']) {
        expect(isPrivateIpv4(bad), isFalse, reason: bad);
      }
    });
  });

  group('model storage', () {
    test('json round trip and old json', () {
      final device = tv(DeviceBrand.lg, '192.168.1.2', model: 'OLED55C1');
      expect(FarlyDevice.fromJson(device.toJson()).model, 'OLED55C1');
      final old = device.toJson()..remove('model');
      expect(FarlyDevice.fromJson(old).model, isNull);
      final hostile = device.toJson()..['model'] = 'a\u0000${'z' * 90}';
      expect(FarlyDevice.fromJson(hostile).model!.length, 60);
    });

    test('merge keeps the model, newer non-empty wins', () {
      final saved = tv(DeviceBrand.lg, '192.168.1.2', model: 'OLD1');
      final keep = mergeDevices(
        saved: [saved],
        found: [tv(DeviceBrand.lg, '192.168.1.2')],
        seenAt: seen,
      );
      expect(keep.single.model, 'OLD1');
      final newer = mergeDevices(
        saved: [saved],
        found: [tv(DeviceBrand.lg, '192.168.1.2', model: 'NEW2')],
        seenAt: seen,
      );
      expect(newer.single.model, 'NEW2');
    });

    test('mac sync keeps the model', () {
      final merged = mergeImportedDevices(
        local: [tv(DeviceBrand.lg, '192.168.1.2')],
        imported: [tv(DeviceBrand.lg, '192.168.1.2', model: 'OLED55C1')],
      );
      expect(merged.single.model, 'OLED55C1');
      final back = mergeImportedDevices(
        local: merged,
        imported: [tv(DeviceBrand.lg, '192.168.1.2')],
      );
      expect(back.single.model, 'OLED55C1');
    });
  });

  group('detail line', () {
    test('brand, model, then tags', () {
      final d = tv(
        DeviceBrand.lg,
        '192.168.1.2',
        name: 'Den',
        model: 'OLED55C1',
      );
      expect(deviceDetailLine(d, ['Last used']), 'LG · OLED55C1 · Last used');
    });

    test('skips a model equal to the name or missing', () {
      final same = tv(
        DeviceBrand.lg,
        '1.1.1.1',
        name: 'oled55c1',
        model: 'OLED55C1',
      );
      expect(deviceDetailLine(same, ['New']), 'LG · New');
      expect(deviceDetailLine(tv(DeviceBrand.roku, '1.1.1.1'), []), 'Roku');
    });

    test('long models are shortened so tags stay', () {
      final d = tv(DeviceBrand.lg, '1.1.1.1', model: 'M' * 50);
      final line = deviceDetailLine(d, ['Paired before']);
      expect(line.endsWith(' · Paired before'), isTrue);
      expect(line.contains('…'), isTrue);
      expect(line.length, lessThan(50));
    });
  });

  group('new tag and duplicates', () {
    test('only never-saved devices are new', () {
      final saved = [tv(DeviceBrand.lg, '192.168.1.2')];
      final found = [
        tv(DeviceBrand.lg, '192.168.1.2'),
        tv(DeviceBrand.roku, '192.168.1.3'),
      ];
      final merged = mergeDevices(saved: saved, found: found, seenAt: seen);
      expect(newlyFoundIds(saved: saved, merged: merged, found: found), {
        'roku@192.168.1.3',
      });
    });

    test('a saved TV that moved address is not new', () {
      final saved = [tv(DeviceBrand.lg, '192.168.1.2', uid: 'abc')];
      final found = [tv(DeviceBrand.lg, '192.168.1.7', uid: 'abc')];
      final merged = mergeDevices(saved: saved, found: found, seenAt: seen);
      expect(
        newlyFoundIds(saved: saved, merged: merged, found: found),
        isEmpty,
      );
    });

    test('one TV on several protocols is one row', () {
      final cast = tv(DeviceBrand.chromecast, '192.168.1.9', uid: 'u1');
      final remote = tv(
        DeviceBrand.androidTv,
        '192.168.1.9',
        model: 'BRAVIA 4K',
      );
      final other = tv(DeviceBrand.androidTv, '192.168.1.10', uid: 'u1');
      final out = collapseDevices([cast, remote, other]);
      expect(out, hasLength(1));
      expect(out.single.model, 'BRAVIA 4K');
      final map = {'192.168.1.9': cast};
      putBetterDevice(map, remote);
      expect(map, hasLength(1));
      expect(map.values.single.brand, DeviceBrand.androidTv);
      expect(map.values.single.model, 'BRAVIA 4K');
    });

    test('same model on two different TVs stays two rows', () {
      final a = tv(DeviceBrand.lg, '192.168.1.2', model: 'OLED55C1', uid: 'a');
      final b = tv(DeviceBrand.lg, '192.168.1.3', model: 'OLED55C1', uid: 'b');
      expect(collapseDevices([a, b]), hasLength(2));
    });
  });
}
