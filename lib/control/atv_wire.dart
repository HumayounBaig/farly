import 'dart:convert';
import 'dart:typed_data';

import '../models/remote_action.dart';

/// Android TV Remote protocol v2: pairing on 6467, keys on 6466.
const atvPairingPort = 6467;
const atvRemotePort = 6466;

const _statusOk = 200;
const _encodingHex = 3;
const _codeLength = 6;
const _roleInput = 1;
const _directionShort = 3;

/// Features Farly asks for: ping, key, IME text, power, volume, and app links.
const atvFeatures = 1 | 2 | 4 | 32 | 64 | 512;

/// Android KEYCODE_DEL — backspace in a focused text field.
const atvKeyDelete = 67;

/// Android KEYCODE_ENTER — submit a focused text field.
const atvKeyEnter = 66;

int? atvKeyCode(RemoteAction action) {
  return switch (action) {
    RemoteAction.up => 19,
    RemoteAction.down => 20,
    RemoteAction.left => 21,
    RemoteAction.right => 22,
    RemoteAction.select => 23,
    RemoteAction.back => 4,
    RemoteAction.home => 3,
    RemoteAction.volumeUp => 24,
    RemoteAction.volumeDown => 25,
    RemoteAction.mute => 164,
    RemoteAction.brightnessUp => 220,
    RemoteAction.brightnessDown => 221,
    RemoteAction.power => 26,
    RemoteAction.play => 85,
    RemoteAction.rewind => 89,
    RemoteAction.forward => 90,
    RemoteAction.menu => atvMenuKeyCode('menu'),
    RemoteAction.input => 178,
  };
}

/// Android / Google TV / TCL menu-like keys people can try.
int? atvMenuKeyCode(String commandId) {
  return switch (commandId) {
    'menu' => 82, // KEYCODE_MENU
    'settings' => 176, // KEYCODE_SETTINGS — common TCL / Google TV menu
    'allApps' => 284, // KEYCODE_ALL_APPS
    'tvContentsMenu' => 256, // KEYCODE_TV_CONTENTS_MENU
    'contextMenu' => 257, // KEYCODE_TV_MEDIA_CONTEXT_MENU
    'info' => 165, // KEYCODE_INFO
    'guide' => 172, // KEYCODE_GUIDE
    _ => null,
  };
}

class ProtoWriter {
  final _bytes = BytesBuilder();

  void varint(int field, int value) {
    _key(field, 0);
    _bytes.add(encodeVarint(value));
  }

  void bytes(int field, List<int> value) {
    _key(field, 2);
    _bytes.add(encodeVarint(value.length));
    _bytes.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, ProtoWriter value) => bytes(field, value.toBytes());

  void _key(int field, int wireType) =>
      _bytes.add(encodeVarint((field << 3) | wireType));

  Uint8List toBytes() => _bytes.toBytes();
}

/// Field number to values: varints come back as [int], length-delimited
/// fields as [Uint8List].
typedef ProtoFields = Map<int, List<Object>>;

ProtoFields decodeProto(Uint8List data) {
  final fields = <int, List<Object>>{};
  var offset = 0;
  (int, int) readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (offset >= data.length) throw const FormatException('Short varint');
      final byte = data[offset++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return (result, offset);
      shift += 7;
    }
  }

  while (offset < data.length) {
    final (key, _) = readVarint();
    final field = key >> 3;
    final Object value;
    switch (key & 7) {
      case 0:
        value = readVarint().$1;
      case 1:
        offset += 8;
        continue;
      case 2:
        final (length, _) = readVarint();
        if (offset + length > data.length) {
          throw const FormatException('Short field');
        }
        value = Uint8List.sublistView(data, offset, offset + length);
        offset += length;
      case 5:
        offset += 4;
        continue;
      default:
        throw const FormatException('Unknown wire type');
    }
    (fields[field] ??= []).add(value);
  }
  return fields;
}

extension ProtoRead on ProtoFields {
  int? integer(int field) {
    final value = this[field]?.first;
    return value is int ? value : null;
  }

  String? string(int field) {
    final value = this[field]?.first;
    if (value is! Uint8List) return null;
    return utf8.decode(value, allowMalformed: true);
  }

  ProtoFields? message(int field) {
    final value = this[field]?.first;
    return value is Uint8List ? decodeProto(value) : null;
  }

  bool has(int field) => containsKey(field);
}

Uint8List encodeVarint(int value) {
  final out = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    out.add((rest & 0x7f) | 0x80);
    rest >>= 7;
  }
  out.add(rest);
  return Uint8List.fromList(out);
}

Uint8List atvFrame(Uint8List message) {
  return (BytesBuilder()
        ..add(encodeVarint(message.length))
        ..add(message))
      .toBytes();
}

/// Splits a TCP stream into varint-prefixed messages.
class AtvFrameReader {
  final _buffer = BytesBuilder();

  List<Uint8List> add(List<int> chunk) {
    _buffer.add(chunk);
    final data = _buffer.toBytes();
    final frames = <Uint8List>[];
    var offset = 0;
    while (true) {
      var length = 0;
      var shift = 0;
      var cursor = offset;
      var complete = false;
      while (cursor < data.length) {
        final byte = data[cursor++];
        length |= (byte & 0x7f) << shift;
        if (byte & 0x80 == 0) {
          complete = true;
          break;
        }
        shift += 7;
      }
      if (!complete || cursor + length > data.length) break;
      frames.add(Uint8List.fromList(data.sublist(cursor, cursor + length)));
      offset = cursor + length;
    }
    _buffer.clear();
    if (offset < data.length) _buffer.add(data.sublist(offset));
    return frames;
  }
}

// Pairing messages. Every one carries protocol version 2 and status OK.

Uint8List _pairing(void Function(ProtoWriter message) body) {
  final message = ProtoWriter()
    ..varint(1, 2)
    ..varint(2, _statusOk);
  body(message);
  return message.toBytes();
}

ProtoWriter _hexEncoding() => ProtoWriter()
  ..varint(1, _encodingHex)
  ..varint(2, _codeLength);

Uint8List atvPairingRequest(String clientName) => _pairing(
  (m) => m.message(
    10,
    ProtoWriter()
      ..string(1, 'atvremote')
      ..string(2, clientName),
  ),
);

Uint8List atvPairingOption() => _pairing(
  (m) => m.message(
    20,
    ProtoWriter()
      ..message(1, _hexEncoding())
      ..varint(3, _roleInput),
  ),
);

Uint8List atvPairingConfiguration() => _pairing(
  (m) => m.message(
    30,
    ProtoWriter()
      ..message(1, _hexEncoding())
      ..varint(2, _roleInput),
  ),
);

Uint8List atvSecretMessage(Uint8List secret) =>
    _pairing((m) => m.message(40, ProtoWriter()..bytes(1, secret)));

enum AtvPairingStep { requestAck, option, configurationAck, secretAck }

class AtvPairingReply {
  const AtvPairingReply({required this.status, this.step});

  final int status;
  final AtvPairingStep? step;

  bool get ok => status == _statusOk;
  bool get badSecret => status == 402;
}

AtvPairingReply parseAtvPairing(Uint8List data) {
  final fields = decodeProto(data);
  final step = fields.has(11)
      ? AtvPairingStep.requestAck
      : fields.has(20)
      ? AtvPairingStep.option
      : fields.has(31)
      ? AtvPairingStep.configurationAck
      : fields.has(41)
      ? AtvPairingStep.secretAck
      : null;
  return AtvPairingReply(status: fields.integer(2) ?? 0, step: step);
}

// Remote messages.

Uint8List atvConfigure(int features) =>
    (ProtoWriter()..message(
          1,
          ProtoWriter()
            ..varint(1, features)
            ..message(
              2,
              ProtoWriter()
                ..varint(3, 1)
                ..string(4, '1')
                ..string(5, 'atvremote')
                ..string(6, '1.0.0'),
            ),
        ))
        .toBytes();

Uint8List atvSetActive(int features) =>
    (ProtoWriter()..message(2, ProtoWriter()..varint(1, features))).toBytes();

Uint8List atvPingResponse(int value) =>
    (ProtoWriter()..message(9, ProtoWriter()..varint(1, value))).toBytes();

Uint8List atvKeyInject(int keyCode) =>
    (ProtoWriter()..message(
          10,
          ProtoWriter()
            ..varint(1, keyCode)
            ..varint(2, _directionShort),
        ))
        .toBytes();

Uint8List atvAppLink(String link) =>
    (ProtoWriter()..message(90, ProtoWriter()..string(1, link))).toBytes();

/// Replaces the half-open range [[start], [end]) in the focused field with
/// [text]. Use equal endpoints to insert. Counters must match the field.
Uint8List atvImeBatchEdit({
  required int imeCounter,
  required int fieldCounter,
  required String text,
  required int start,
  required int end,
}) {
  final imeObject = ProtoWriter()
    ..varint(1, start)
    ..varint(2, end)
    ..string(3, text);
  final editInfo = ProtoWriter()
    ..varint(1, 1)
    ..message(2, imeObject);
  return (ProtoWriter()..message(
        21,
        ProtoWriter()
          ..varint(1, imeCounter)
          ..varint(2, fieldCounter)
          ..message(3, editInfo),
      ))
      .toBytes();
}

/// Android KEYCODE for one printable ASCII character, when IME is unavailable.
int? atvCharKeyCode(String character) {
  if (character.length != 1) return null;
  final unit = character.codeUnitAt(0);
  if (unit >= 0x61 && unit <= 0x7a) return 29 + (unit - 0x61); // a-z
  if (unit >= 0x41 && unit <= 0x5a) return 29 + (unit - 0x41); // A-Z
  if (unit >= 0x30 && unit <= 0x39) return 7 + (unit - 0x30); // 0-9
  return switch (character) {
    ' ' => 62,
    '@' => 77,
    '.' => 56,
    ',' => 55,
    '-' => 69,
    '=' => 70,
    '/' => 76,
    '+' => 81,
    '*' => 17,
    '#' => 18,
    '\n' => 66,
    _ => null,
  };
}

sealed class AtvRemoteEvent {
  const AtvRemoteEvent();
}

class AtvConfigureEvent extends AtvRemoteEvent {
  const AtvConfigureEvent(this.features);
  final int features;
}

class AtvSetActiveEvent extends AtvRemoteEvent {
  const AtvSetActiveEvent();
}

class AtvPingEvent extends AtvRemoteEvent {
  const AtvPingEvent(this.value);
  final int value;
}

/// The TV is ready for keys.
class AtvStartEvent extends AtvRemoteEvent {
  const AtvStartEvent();
}

class AtvErrorEvent extends AtvRemoteEvent {
  const AtvErrorEvent();
}

class AtvOtherEvent extends AtvRemoteEvent {
  const AtvOtherEvent();
}

/// Focused text field counters from the TV (IME key inject or show request).
class AtvImeFocusEvent extends AtvRemoteEvent {
  const AtvImeFocusEvent({
    required this.imeCounter,
    required this.fieldCounter,
    this.fromKeyInject = false,
    this.fieldValue = '',
    this.fieldLabel = '',
    this.hasFieldStatus = false,
  });

  final int imeCounter;
  final int fieldCounter;
  final bool fromKeyInject;
  final String fieldValue;
  final String fieldLabel;
  final bool hasFieldStatus;
}

class AtvImeBatchEchoEvent extends AtvRemoteEvent {
  const AtvImeBatchEchoEvent({
    required this.imeCounter,
    required this.fieldCounter,
  });

  final int imeCounter;
  final int fieldCounter;
}

AtvRemoteEvent parseAtvRemote(Uint8List data) {
  final fields = decodeProto(data);
  final configure = fields.message(1);
  if (configure != null) return AtvConfigureEvent(configure.integer(1) ?? 0);
  if (fields.has(2)) return const AtvSetActiveEvent();
  if (fields.has(3)) return const AtvErrorEvent();
  final ping = fields.message(8);
  if (ping != null) return AtvPingEvent(ping.integer(1) ?? 0);
  final imeInject = fields.message(20);
  if (imeInject != null) {
    final status = imeInject.message(2);
    return AtvImeFocusEvent(
      imeCounter: imeInject.message(1)?.integer(1) ?? 0,
      fieldCounter: status?.integer(1) ?? 0,
      fromKeyInject: true,
      fieldValue: status?.string(2) ?? '',
      fieldLabel: status?.string(6) ?? '',
      hasFieldStatus: status != null,
    );
  }
  final batch = fields.message(21);
  if (batch != null) {
    return AtvImeBatchEchoEvent(
      imeCounter: batch.integer(1) ?? 0,
      fieldCounter: batch.integer(2) ?? 0,
    );
  }
  final show = fields.message(22);
  if (show != null) {
    final status = show.message(2);
    return AtvImeFocusEvent(
      imeCounter: 0,
      fieldCounter: status?.integer(1) ?? 0,
      fieldValue: status?.string(2) ?? '',
      fieldLabel: status?.string(6) ?? '',
      hasFieldStatus: status != null,
    );
  }
  if (fields.has(40)) return const AtvStartEvent();
  return const AtvOtherEvent();
}
