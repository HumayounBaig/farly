import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('app.getfarly.farly/menu');

/// Menu-bar glyph style: system-tinted template, or full Farly color mark.
enum MenuBarIconStyle {
  monotone,
  color;

  static MenuBarIconStyle parse(String? raw) {
    return switch (raw) {
      'color' => MenuBarIconStyle.color,
      _ => MenuBarIconStyle.monotone,
    };
  }

  String get wire => name;
}

/// Quits the menu-bar companion via AppKit so the status item clears cleanly.
Future<void> quitCompanion() async {
  try {
    await _channel.invokeMethod<void>('quit');
  } catch (_) {
    exit(0);
  }
}

/// Asks macOS for Local Network access (needed to reach the phone / TVs).
Future<void> ensureLocalNetworkAccess() async {
  try {
    await _channel.invokeMethod<void>('ensureLocalNetwork');
  } catch (_) {
    // Older builds without the channel still try the HTTP path.
  }
}

Future<MenuBarIconStyle> getMenuBarIconStyle() async {
  try {
    final raw = await _channel.invokeMethod<String>('getMenuBarIconStyle');
    return MenuBarIconStyle.parse(raw);
  } catch (_) {
    return MenuBarIconStyle.monotone;
  }
}

Future<MenuBarIconStyle> setMenuBarIconStyle(MenuBarIconStyle style) async {
  try {
    final raw = await _channel.invokeMethod<String>(
      'setMenuBarIconStyle',
      style.wire,
    );
    return MenuBarIconStyle.parse(raw);
  } catch (_) {
    return style;
  }
}
