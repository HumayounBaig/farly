import 'dart:convert';

import '../models/remote_action.dart';

String? samsungKey(RemoteAction action) {
  return switch (action) {
    RemoteAction.up => 'KEY_UP',
    RemoteAction.down => 'KEY_DOWN',
    RemoteAction.left => 'KEY_LEFT',
    RemoteAction.right => 'KEY_RIGHT',
    RemoteAction.select => 'KEY_ENTER',
    RemoteAction.back => 'KEY_RETURN',
    RemoteAction.home => 'KEY_HOME',
    RemoteAction.volumeUp => 'KEY_VOLUP',
    RemoteAction.volumeDown => 'KEY_VOLDOWN',
    RemoteAction.mute => 'KEY_MUTE',
    RemoteAction.brightnessUp => 'KEY_BRIGHTNESS_UP',
    RemoteAction.brightnessDown => 'KEY_BRIGHTNESS_DOWN',
    RemoteAction.power => 'KEY_POWER',
    RemoteAction.play => 'KEY_PLAY',
    RemoteAction.rewind => 'KEY_REWIND',
    RemoteAction.forward => 'KEY_FF',
    RemoteAction.menu => samsungMenuKey('menu'),
    RemoteAction.input => 'KEY_SOURCE',
  };
}

String? samsungMenuKey(String commandId) {
  return switch (commandId) {
    'menu' => 'KEY_MENU',
    'tools' => 'KEY_TOOLS',
    'contents' => 'KEY_CONTENTS',
    'guide' => 'KEY_GUIDE',
    'info' => 'KEY_INFO',
    _ => null,
  };
}

Map<String, dynamic> samsungKeyPayload(String key) {
  return {
    'method': 'ms.remote.control',
    'params': {
      'Cmd': 'Click',
      'DataOfCmd': key,
      'Option': 'false',
      'TypeOfRemote': 'SendRemoteKey',
    },
  };
}

/// Types [text] into the focused Samsung on-screen field.
Map<String, dynamic> samsungTextPayload(String text) {
  return {
    'method': 'ms.remote.control',
    'params': {
      'Cmd': 'WriteString',
      'DataOfCmd': text,
      'TypeOfRemote': 'SendInputString',
    },
  };
}

Uri samsungSocketUri({
  required String host,
  required bool secure,
  String? token,
}) {
  return Uri(
    scheme: secure ? 'wss' : 'ws',
    host: host,
    port: secure ? 8002 : 8001,
    path: '/api/v2/channels/samsung.remote.control',
    queryParameters: {
      'name': base64Encode(utf8.encode('Farly')),
      if (token != null && token.isNotEmpty) 'token': token,
    },
  );
}

/// Samsung remote key for one character, used when no TV IME session is open
/// (YouTube's own search keyboard never fires `ms.remote.imeStart`).
/// Letters are unverified on real TVs; digits are standard remote keys.
String? samsungCharKey(String character) {
  if (character.length != 1) return null;
  final unit = character.toUpperCase().codeUnitAt(0);
  if (unit >= 0x41 && unit <= 0x5a || unit >= 0x30 && unit <= 0x39) {
    return 'KEY_${String.fromCharCode(unit)}';
  }
  return switch (character) {
    ' ' => 'KEY_SPACE',
    '-' => 'KEY_MINUS',
    '.' => 'KEY_DOT',
    _ => null,
  };
}
