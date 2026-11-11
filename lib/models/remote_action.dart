import 'package:flutter/material.dart';

enum RemoteAction {
  up('Up'),
  down('Down'),
  left('Left'),
  right('Right'),
  select('Select'),
  back('Back'),
  home('Home'),
  volumeUp('Volume up'),
  volumeDown('Volume down'),
  mute('Mute'),
  power('Power'),
  play('Play'),
  rewind('Rewind'),
  forward('Forward'),
  input('Input');

  const RemoteAction(this.label);

  final String label;
}

class AppShortcut {
  const AppShortcut({
    required this.label,
    required this.id,
    this.mark,
    this.tint,
    this.catalogId,
  });

  /// Convenience for the older positional form used in tests and sessions.
  factory AppShortcut.plain(String label, String id) =>
      AppShortcut(label: label, id: id);

  final String label;

  /// Platform launch target: Roku channel id or Android TV app link / URL.
  final String id;

  /// Short brand mark drawn on the button (N, ▶, …).
  final String? mark;
  final Color? tint;

  /// Catalog id from [StreamApp], or `custom`.
  final String? catalogId;
}
