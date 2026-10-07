import 'dart:typed_data';

import '../models/farly_device.dart';

class BroadlinkHub {
  const BroadlinkHub({
    required this.name,
    required this.deviceType,
    required this.mac,
  });

  final String name;
  final int deviceType;
  final String mac;
}

/// 48-byte Broadlink discovery hello. Checksum covers the packet before the
/// checksum bytes are written, matching the local hub protocol.
Uint8List buildBroadlinkHello({
  required String localIp,
  required int localPort,
  DateTime? now,
}) {
  final packet = Uint8List(0x30);
  final time = now ?? DateTime.now();
  final offset = ByteData(4)
    ..setInt32(0, time.timeZoneOffset.inHours, Endian.little);
  packet.setRange(0x08, 0x0c, offset.buffer.asUint8List());
  final year = ByteData(2)..setUint16(0, time.year, Endian.little);
  packet.setRange(0x0c, 0x0e, year.buffer.asUint8List());
  packet[0x0e] = time.second;
  packet[0x0f] = time.minute;
  packet[0x10] = time.hour;
  packet[0x11] = time.weekday;
  packet[0x12] = time.day;
  packet[0x13] = time.month;

  final parts = localIp.split('.');
  if (parts.length == 4) {
    final octets = parts.map(int.parse).toList();
    packet[0x18] = octets[3];
    packet[0x19] = octets[2];
    packet[0x1a] = octets[1];
    packet[0x1b] = octets[0];
  }
  packet[0x1c] = localPort & 0xff;
  packet[0x1d] = (localPort >> 8) & 0xff;
  packet[0x26] = 6;

  var checksum = 0xBEAF;
  for (final byte in packet) {
    checksum = (checksum + byte) & 0xFFFF;
  }
  packet[0x20] = checksum & 0xff;
  packet[0x21] = (checksum >> 8) & 0xff;
  return packet;
}

BroadlinkHub? parseBroadlinkHello(Uint8List packet) {
  if (packet.length < 0x80) return null;
  final deviceType = packet[0x34] | (packet[0x35] << 8);
  if (deviceType == 0) return null;
  final nameBytes = packet.sublist(0x40);
  final zero = nameBytes.indexOf(0);
  final sliced = nameBytes.sublist(0, zero < 0 ? nameBytes.length : zero);
  final name = String.fromCharCodes(sliced).trim();
  final mac = packet
      .sublist(0x3a, 0x40)
      .reversed
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join(':');
  return BroadlinkHub(
    name: name.isEmpty ? DeviceBrand.broadlink.label : name,
    deviceType: deviceType,
    mac: mac,
  );
}
