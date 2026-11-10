import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The client certificate an Android TV remembers after pairing.
class AtvIdentity {
  const AtvIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  final String certificatePem;
  final String privateKeyPem;

  Uint8List get certificateDer => pemBody(certificatePem);
}

AtvIdentity createAtvIdentity({int bits = 2048, DateTime? now}) {
  final random = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ),
    );
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  final public = pair.publicKey;
  final private = pair.privateKey;

  final issued = (now ?? DateTime.now()).toUtc();
  final name = _seq([
    _set([
      _seq([_oid(_commonName), _utf8('Farly')]),
    ]),
  ]);
  final algorithm = _seq([_oid(_sha256WithRsa), _null()]);
  final tbs = _seq([
    _explicit(0, _int(BigInt.two)),
    _int(BigInt.from(issued.millisecondsSinceEpoch)),
    algorithm,
    name,
    _seq([
      _utcTime(issued.subtract(const Duration(days: 1))),
      _utcTime(DateTime.utc(2049, 12, 31)),
    ]),
    name,
    _publicKeyInfo(public),
  ]);
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(private));
  final signature = signer.generateSignature(Uint8List.fromList(tbs)).bytes;
  final certificate = _seq([tbs, algorithm, _bitString(signature)]);

  final p = private.p!;
  final q = private.q!;
  final d = private.privateExponent!;
  final key = _seq([
    _int(BigInt.zero),
    _int(public.modulus!),
    _int(public.exponent!),
    _int(d),
    _int(p),
    _int(q),
    _int(d % (p - BigInt.one)),
    _int(d % (q - BigInt.one)),
    _int(q.modInverse(p)),
  ]);
  return AtvIdentity(
    certificatePem: _pem('CERTIFICATE', certificate),
    privateKeyPem: _pem('RSA PRIVATE KEY', key),
  );
}

class RsaPublicNumbers {
  const RsaPublicNumbers(this.modulus, this.exponent);

  /// Unsigned big-endian bytes with no leading zeros.
  final Uint8List modulus;
  final Uint8List exponent;
}

/// Reads the RSA modulus and exponent from a DER X.509 certificate.
RsaPublicNumbers? rsaPublicNumbers(Uint8List certificateDer) {
  try {
    return _findRsaKey(_Der.parse(certificateDer, 0));
  } catch (_) {
    return null;
  }
}

/// The 32-byte secret the TV expects for a six-character hex code, or null
/// when the code cannot be right for these two certificates.
Uint8List? atvPairingSecret({
  required Uint8List clientCertificateDer,
  required Uint8List serverCertificateDer,
  required String code,
}) {
  final clean = normalizeAtvCode(code);
  if (clean == null) return null;
  final client = rsaPublicNumbers(clientCertificateDer);
  final server = rsaPublicNumbers(serverCertificateDer);
  if (client == null || server == null) return null;
  final digest = SHA256Digest();
  for (final part in [
    client.modulus,
    client.exponent,
    server.modulus,
    server.exponent,
    _hex(clean.substring(2)),
  ]) {
    digest.update(part, 0, part.length);
  }
  final hash = Uint8List(digest.digestSize);
  digest.doFinal(hash, 0);
  if (hash[0] != int.parse(clean.substring(0, 2), radix: 16)) return null;
  return hash;
}

String? normalizeAtvCode(String code) {
  final clean = code.replaceAll(RegExp(r'\s'), '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(clean) ? clean : null;
}

Uint8List pemBody(String pem) {
  final body = pem
      .split('\n')
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

String _pem(String label, List<int> der) {
  final encoded = base64.encode(der);
  final lines = [
    for (var i = 0; i < encoded.length; i += 64)
      encoded.substring(i, min(i + 64, encoded.length)),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

const _commonName = [2, 5, 4, 3];
const _sha256WithRsa = [1, 2, 840, 113549, 1, 1, 11];
const _rsaEncryption = [1, 2, 840, 113549, 1, 1, 1];

List<int> _publicKeyInfo(RSAPublicKey key) => _seq([
  _seq([_oid(_rsaEncryption), _null()]),
  _bitString(_seq([_int(key.modulus!), _int(key.exponent!)])),
]);

List<int> _tlv(int tag, List<int> content) {
  final length = content.length;
  final List<int> lengthBytes;
  if (length < 0x80) {
    lengthBytes = [length];
  } else {
    final bytes = <int>[];
    for (var rest = length; rest > 0; rest >>= 8) {
      bytes.insert(0, rest & 0xff);
    }
    lengthBytes = [0x80 | bytes.length, ...bytes];
  }
  return [tag, ...lengthBytes, ...content];
}

List<int> _seq(List<List<int>> items) =>
    _tlv(0x30, items.expand((i) => i).toList());

List<int> _set(List<List<int>> items) =>
    _tlv(0x31, items.expand((i) => i).toList());

List<int> _explicit(int number, List<int> content) =>
    _tlv(0xa0 | number, content);

List<int> _null() => const [0x05, 0x00];

List<int> _utf8(String value) => _tlv(0x0c, utf8.encode(value));

List<int> _bitString(List<int> bytes) => _tlv(0x03, [0, ...bytes]);

List<int> _int(BigInt value) {
  final bytes = _unsigned(value);
  if (bytes.isEmpty || bytes[0] & 0x80 != 0) bytes.insert(0, 0);
  return _tlv(0x02, bytes);
}

List<int> _unsigned(BigInt value) {
  final bytes = <int>[];
  for (var rest = value; rest > BigInt.zero; rest >>= 8) {
    bytes.insert(0, (rest & BigInt.from(0xff)).toInt());
  }
  return bytes;
}

List<int> _oid(List<int> parts) {
  final bytes = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    for (var rest = part >> 7; rest > 0; rest >>= 7) {
      chunk.insert(0, (rest & 0x7f) | 0x80);
    }
    bytes.addAll(chunk);
  }
  return _tlv(0x06, bytes);
}

List<int> _utcTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final text =
      '${two(time.year % 100)}${two(time.month)}${two(time.day)}'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}Z';
  return _tlv(0x17, ascii.encode(text));
}

class _Der {
  _Der(this.tag, this.value, this.end);

  final int tag;
  final Uint8List value;
  final int end;

  bool get constructed => tag & 0x20 != 0;

  List<_Der> get children {
    final nodes = <_Der>[];
    var offset = 0;
    while (offset < value.length) {
      final node = _Der.parse(value, offset);
      nodes.add(node);
      offset = node.end;
    }
    return nodes;
  }

  static _Der parse(Uint8List data, int offset) {
    final tag = data[offset];
    var cursor = offset + 1;
    var length = data[cursor++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | data[cursor++];
      }
    }
    if (cursor + length > data.length) throw const FormatException('Short DER');
    return _Der(
      tag,
      Uint8List.sublistView(data, cursor, cursor + length),
      cursor + length,
    );
  }
}

final _rsaOidBytes = Uint8List.fromList(_oid(_rsaEncryption).sublist(2));

RsaPublicNumbers? _findRsaKey(_Der node) {
  if (!node.constructed) return null;
  final children = node.children;
  if (node.tag == 0x30 &&
      children.length == 2 &&
      children[0].tag == 0x30 &&
      children[1].tag == 0x03) {
    final algorithm = children[0].children;
    if (algorithm.isNotEmpty &&
        algorithm[0].tag == 0x06 &&
        _same(algorithm[0].value, _rsaOidBytes)) {
      final bits = children[1].value;
      final key = _Der.parse(Uint8List.sublistView(bits, 1), 0).children;
      return RsaPublicNumbers(_strip(key[0].value), _strip(key[1].value));
    }
  }
  for (final child in children) {
    final found = _findRsaKey(child);
    if (found != null) return found;
  }
  return null;
}

Uint8List _strip(Uint8List bytes) {
  var start = 0;
  while (start < bytes.length - 1 && bytes[start] == 0) {
    start++;
  }
  return Uint8List.sublistView(bytes, start);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
