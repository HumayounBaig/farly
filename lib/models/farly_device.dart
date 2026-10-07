enum DeviceKind { screen, climate }

enum DeviceBrand {
  samsung,
  lg,
  roku,
  androidTv,
  appleTv,
  chromecast,
  sony,
  broadlink,
  otherAc,
  unknown,
  preview,
}

extension DeviceBrandDetails on DeviceBrand {
  String get label => switch (this) {
    DeviceBrand.samsung => 'Samsung',
    DeviceBrand.lg => 'LG',
    DeviceBrand.roku => 'Roku',
    DeviceBrand.androidTv => 'Android TV',
    DeviceBrand.appleTv => 'Apple TV',
    DeviceBrand.chromecast => 'Chromecast',
    DeviceBrand.sony => 'Sony',
    DeviceBrand.broadlink => 'Infrared hub',
    DeviceBrand.otherAc => 'Air conditioner',
    DeviceBrand.unknown => 'Device',
    DeviceBrand.preview => 'Preview',
  };

  DeviceKind get kind => switch (this) {
    DeviceBrand.broadlink || DeviceBrand.otherAc => DeviceKind.climate,
    _ => DeviceKind.screen,
  };

  int? get defaultPort => switch (this) {
    DeviceBrand.samsung => 8002,
    DeviceBrand.lg => 3000,
    DeviceBrand.roku => 8060,
    DeviceBrand.androidTv => 6466,
    DeviceBrand.broadlink => 80,
    _ => null,
  };

  bool get commandsReady => switch (this) {
    DeviceBrand.samsung || DeviceBrand.lg || DeviceBrand.roku => true,
    _ => false,
  };

  /// Why Farly can see this device without driving it yet.
  String? get limitation => switch (this) {
    DeviceBrand.androidTv =>
      'Farly found this Android TV. It asks for a pairing code, and that handshake is not in this build yet.',
    DeviceBrand.appleTv =>
      'Farly found this Apple TV. Its pairing handshake is not in this build yet.',
    DeviceBrand.chromecast =>
      'Farly found this Cast device. It announces itself, but it does not accept remote buttons.',
    DeviceBrand.sony =>
      'Farly found this Sony TV. Its local control key is not in this build yet.',
    DeviceBrand.broadlink || DeviceBrand.otherAc =>
      'Farly found this on your network. Infrared and cloud air-conditioner commands are not in this build yet.',
    DeviceBrand.unknown =>
      'Farly can see this device, but it does not have a control path for it yet.',
    _ => null,
  };

  /// Lower is a better match when one address announces several services.
  int get rank => switch (this) {
    DeviceBrand.roku => 0,
    DeviceBrand.samsung => 1,
    DeviceBrand.lg => 2,
    DeviceBrand.androidTv => 3,
    DeviceBrand.sony => 4,
    DeviceBrand.appleTv => 5,
    DeviceBrand.broadlink => 6,
    DeviceBrand.otherAc => 7,
    DeviceBrand.chromecast => 8,
    DeviceBrand.unknown => 9,
    DeviceBrand.preview => 10,
  };
}

class FarlyDevice {
  const FarlyDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.brand,
    this.host,
    this.port,
    this.token,
    this.clientKey,
    this.descriptionUrl,
    this.source = 'scan',
    this.lastSeen,
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final DeviceBrand brand;
  final String? host;
  final int? port;
  final String? token;
  final String? clientKey;
  final String? descriptionUrl;
  final String source;
  final DateTime? lastSeen;

  static String idFor(DeviceBrand brand, String host) => '${brand.name}@$host';

  static const preview = FarlyDevice(
    id: 'preview',
    name: 'Preview',
    kind: DeviceKind.screen,
    brand: DeviceBrand.preview,
    source: 'preview',
  );

  FarlyDevice copyWith({
    String? name,
    String? token,
    String? clientKey,
    String? descriptionUrl,
    DateTime? lastSeen,
    bool clearToken = false,
  }) {
    return FarlyDevice(
      id: id,
      name: name ?? this.name,
      kind: kind,
      brand: brand,
      host: host,
      port: port,
      token: clearToken ? null : token ?? this.token,
      clientKey: clientKey ?? this.clientKey,
      descriptionUrl: descriptionUrl ?? this.descriptionUrl,
      source: source,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'brand': brand.name,
    'host': host,
    'port': port,
    'token': token,
    'clientKey': clientKey,
    'descriptionUrl': descriptionUrl,
    'source': source,
    'lastSeen': lastSeen?.toIso8601String(),
  };

  factory FarlyDevice.fromJson(Map<String, dynamic> json) {
    return FarlyDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Device',
      kind: DeviceKind.values.byName(json['kind'] as String? ?? 'screen'),
      brand: DeviceBrand.values.byName(json['brand'] as String? ?? 'unknown'),
      host: json['host'] as String?,
      port: json['port'] as int?,
      token: json['token'] as String?,
      clientKey: json['clientKey'] as String?,
      descriptionUrl: json['descriptionUrl'] as String?,
      source: json['source'] as String? ?? 'scan',
      lastSeen: json['lastSeen'] == null
          ? null
          : DateTime.tryParse(json['lastSeen'] as String),
    );
  }
}

bool isIpv4Address(String value) {
  final parts = value.trim().split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final number = int.tryParse(part);
    if (number == null || number < 0 || number > 255) return false;
  }
  return true;
}
