import 'package:flutter/material.dart';

import 'farly_device.dart';
import 'remote_action.dart';

/// A streaming service Farly can put on the remote's app buttons.
class StreamApp {
  const StreamApp({
    required this.id,
    required this.label,
    required this.mark,
    required this.tint,
    this.rokuChannelId,
    this.androidUrl,
  });

  final String id;
  final String label;

  /// Letter or short mark drawn on the button (Netflix → N, YouTube → ▶).
  final String mark;
  final Color tint;
  final String? rokuChannelId;
  final String? androidUrl;

  bool supports(DeviceBrand brand) {
    if (brand == DeviceBrand.roku) return rokuChannelId != null;
    if (brand == DeviceBrand.androidTv || brand == DeviceBrand.chromecast) {
      return androidUrl != null;
    }
    return false;
  }

  AppShortcut shortcutFor(DeviceBrand brand) {
    final target = switch (brand) {
      DeviceBrand.roku => rokuChannelId ?? id,
      _ => androidUrl ?? id,
    };
    return AppShortcut(
      label: label,
      id: target,
      mark: mark,
      tint: tint,
      catalogId: id,
    );
  }

  static const netflix = StreamApp(
    id: 'netflix',
    label: 'Netflix',
    mark: 'N',
    tint: Color(0xFFE50914),
    rokuChannelId: '12',
    androidUrl: 'https://www.netflix.com/title',
  );

  static const youtube = StreamApp(
    id: 'youtube',
    label: 'YouTube',
    mark: '▶',
    tint: Color(0xFFFF0000),
    rokuChannelId: '837',
    androidUrl: 'https://www.youtube.com',
  );

  static const disney = StreamApp(
    id: 'disney',
    label: 'Disney+',
    mark: 'D',
    tint: Color(0xFF113CCF),
    rokuChannelId: '291097',
    androidUrl: 'https://www.disneyplus.com',
  );

  static const prime = StreamApp(
    id: 'prime',
    label: 'Prime Video',
    mark: 'P',
    tint: Color(0xFF00A8E1),
    rokuChannelId: '13',
    androidUrl: 'https://www.amazon.com/gp/video/storefront',
  );

  static const hulu = StreamApp(
    id: 'hulu',
    label: 'Hulu',
    mark: 'h',
    tint: Color(0xFF1CE783),
    rokuChannelId: '2285',
    androidUrl: 'https://www.hulu.com',
  );

  static const max = StreamApp(
    id: 'max',
    label: 'Max',
    mark: 'M',
    tint: Color(0xFF002BE7),
    rokuChannelId: '61322',
    androidUrl: 'https://www.max.com',
  );

  static const spotify = StreamApp(
    id: 'spotify',
    label: 'Spotify',
    mark: '♪',
    tint: Color(0xFF1DB954),
    rokuChannelId: '22297',
    androidUrl: 'https://open.spotify.com',
  );

  static const appleTv = StreamApp(
    id: 'appletv',
    label: 'Apple TV',
    mark: '',
    tint: Color(0xFFA2AAAD),
    rokuChannelId: '551012',
    androidUrl: 'https://tv.apple.com',
  );

  static const plex = StreamApp(
    id: 'plex',
    label: 'Plex',
    mark: 'P',
    tint: Color(0xFFE5A00D),
    rokuChannelId: '13535',
    androidUrl: 'https://app.plex.tv',
  );

  static const twitch = StreamApp(
    id: 'twitch',
    label: 'Twitch',
    mark: 'T',
    tint: Color(0xFF9146FF),
    rokuChannelId: '19976',
    androidUrl: 'https://www.twitch.tv',
  );

  static const youtubeMusic = StreamApp(
    id: 'youtubemusic',
    label: 'YT Music',
    mark: '♫',
    tint: Color(0xFFFF0000),
    rokuChannelId: '221584',
    androidUrl: 'https://music.youtube.com',
  );

  static const catalog = <StreamApp>[
    netflix,
    youtube,
    disney,
    prime,
    hulu,
    max,
    spotify,
    appleTv,
    plex,
    twitch,
    youtubeMusic,
  ];

  static const defaults = <StreamApp>[netflix, youtube];

  static StreamApp? byId(String? id) {
    if (id == null || id.isEmpty || id == ShortcutSlot.customId) return null;
    for (final app in catalog) {
      if (app.id == id) return app;
    }
    return null;
  }
}

/// One of the two app buttons on the remote.
class ShortcutSlot {
  const ShortcutSlot({
    required this.appId,
    this.customLabel,
    this.customRokuId,
    this.customUrl,
  });

  static const customId = 'custom';
  static const count = 2;

  final String appId;
  final String? customLabel;
  final String? customRokuId;
  final String? customUrl;

  bool get isCustom => appId == customId;

  static List<ShortcutSlot> get defaults => [
    for (final app in StreamApp.defaults) ShortcutSlot(appId: app.id),
  ];

  AppShortcut toShortcut(DeviceBrand brand) {
    final catalog = StreamApp.byId(appId);
    if (catalog != null) return catalog.shortcutFor(brand);

    final label = (customLabel == null || customLabel!.trim().isEmpty)
        ? 'App'
        : customLabel!.trim();
    final target = switch (brand) {
      DeviceBrand.roku =>
        (customRokuId == null || customRokuId!.trim().isEmpty)
            ? '12'
            : customRokuId!.trim(),
      _ => (customUrl == null || customUrl!.trim().isEmpty)
          ? 'https://www.youtube.com'
          : _normalizeUrl(customUrl!.trim()),
    };
    final mark = label.isEmpty
        ? '?'
        : String.fromCharCode(label.runes.first).toUpperCase();
    return AppShortcut(
      label: label,
      id: target,
      mark: mark,
      tint: const Color(0xFFF0B26A),
      catalogId: customId,
    );
  }

  Map<String, dynamic> toJson() => {
    'appId': appId,
    if (customLabel != null) 'customLabel': customLabel,
    if (customRokuId != null) 'customRokuId': customRokuId,
    if (customUrl != null) 'customUrl': customUrl,
  };

  factory ShortcutSlot.fromJson(Map<String, dynamic> json) {
    return ShortcutSlot(
      appId: json['appId'] as String? ?? StreamApp.netflix.id,
      customLabel: json['customLabel'] as String?,
      customRokuId: json['customRokuId'] as String?,
      customUrl: json['customUrl'] as String?,
    );
  }

  static String _normalizeUrl(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'https://$value';
  }
}
