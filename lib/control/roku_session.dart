import 'package:http/http.dart' as http;

import '../models/farly_device.dart';
import '../models/menu_command.dart';
import '../models/remote_action.dart';
import '../models/stream_app.dart';
import 'remote_session.dart';

/// Roku literal-key path for one typed character.
String rokuLitPath(String character) {
  final encoded = Uri.encodeComponent(character);
  return 'Lit_$encoded';
}

String? rokuKey(RemoteAction action) {
  return switch (action) {
    RemoteAction.up => 'Up',
    RemoteAction.down => 'Down',
    RemoteAction.left => 'Left',
    RemoteAction.right => 'Right',
    RemoteAction.select => 'Select',
    RemoteAction.back => 'Back',
    RemoteAction.home => 'Home',
    RemoteAction.volumeUp => 'VolumeUp',
    RemoteAction.volumeDown => 'VolumeDown',
    RemoteAction.mute => 'VolumeMute',
    RemoteAction.brightnessUp => null,
    RemoteAction.brightnessDown => null,
    RemoteAction.power => 'Power',
    RemoteAction.play => 'Play',
    RemoteAction.rewind => 'Rev',
    RemoteAction.forward => 'Fwd',
    RemoteAction.menu => rokuMenuKey('info'),
    RemoteAction.input => null,
  };
}

String? rokuMenuKey(String commandId) {
  return switch (commandId) {
    'info' => 'Info',
    'search' => 'Search',
    'replay' => 'InstantReplay',
    _ => null,
  };
}

class RokuSession extends RemoteSession {
  RokuSession({required this.device, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  FarlyDevice device;
  final http.Client _client;
  final bool _ownsClient;
  final _updates = SessionUpdates();
  var _isTv = false;

  static final apps = [
    StreamApp.netflix.shortcutFor(DeviceBrand.roku),
    StreamApp.youtube.shortcutFor(DeviceBrand.roku),
  ];

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  void rebind(FarlyDevice device) => this.device = device;

  @override
  List<AppShortcut> get shortcuts => apps;

  @override
  bool supports(RemoteAction action) => rokuKey(action) != null;

  @override
  bool get supportsText => true;

  // Roku TVs only offer "Turn off screen" in the Info (*) options menu.
  @override
  PictureOffSupport get pictureOffSupport =>
      _isTv ? PictureOffSupport.menu : PictureOffSupport.none;

  @override
  Future<CommandResult> setPictureOff({required bool off}) async {
    final host = device.host;
    if (!_isTv || host == null) {
      return const CommandResult(false, 'This Roku cannot turn its picture off.');
    }
    final result = await _post(Uri.parse('http://$host:8060/keypress/Info'));
    return result.ok
        ? const CommandResult(true, 'Choose Turn off screen on the TV')
        : result;
  }

  @override
  Future<void> open() async {
    final host = device.host;
    if (host == null) {
      _updates.add(
        const SessionUpdate(
          SessionPhase.failed,
          detail: 'This Roku has no address.',
        ),
      );
      return;
    }
    try {
      final response = await _client
          .get(Uri.parse('http://$host:8060/query/device-info'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _isTv = response.body.contains('<is-tv>true</is-tv>');
        _updates.add(
          const SessionUpdate(SessionPhase.ready, detail: 'Connected'),
        );
        return;
      }
      _updates.add(
        SessionUpdate(
          SessionPhase.failed,
          detail: 'The Roku answered ${response.statusCode}.',
        ),
      );
    } catch (_) {
      _updates.add(
        const SessionUpdate(
          SessionPhase.failed,
          detail: 'Could not reach this Roku.',
        ),
      );
    }
  }

  @override
  bool get supportsMenuProbes => true;

  @override
  Future<CommandResult> send(RemoteAction action) async {
    final host = device.host;
    if (host == null) {
      return const CommandResult(false, 'This button is not on a Roku.');
    }
    final key = action == RemoteAction.menu
        ? rokuMenuKey(MenuCommand.resolvedId(device))
        : rokuKey(action);
    if (key == null) {
      return const CommandResult(false, 'This button is not on a Roku.');
    }
    return _post(Uri.parse('http://$host:8060/keypress/$key'));
  }

  @override
  Future<CommandResult> sendMenuProbe(String commandId) async {
    final host = device.host;
    final key = rokuMenuKey(commandId);
    if (host == null || key == null) {
      return const CommandResult(false, 'This button is not on a Roku.');
    }
    return _post(Uri.parse('http://$host:8060/keypress/$key'));
  }

  @override
  Future<CommandResult> sendText(String text) async {
    final host = device.host;
    if (host == null) {
      return const CommandResult(false, 'This Roku has no address.');
    }
    if (text.isEmpty) {
      return const CommandResult(false, 'Nothing to type.');
    }
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final result = await _post(
        Uri.parse('http://$host:8060/keypress/${rokuLitPath(character)}'),
      );
      if (!result.ok) return result;
    }
    return const CommandResult(true);
  }

  @override
  Future<CommandResult> textBackspace() async {
    final host = device.host;
    if (host == null) {
      return const CommandResult(false, 'This Roku has no address.');
    }
    return _post(Uri.parse('http://$host:8060/keypress/Backspace'));
  }

  @override
  Future<CommandResult> textEnter() async {
    final host = device.host;
    if (host == null) {
      return const CommandResult(false, 'This Roku has no address.');
    }
    return _post(Uri.parse('http://$host:8060/keypress/Enter'));
  }

  @override
  Future<CommandResult> launch(AppShortcut shortcut) async {
    final host = device.host;
    if (host == null) {
      return const CommandResult(false, 'This Roku has no address.');
    }
    return _post(Uri.parse('http://$host:8060/launch/${shortcut.id}'));
  }

  Future<CommandResult> _post(Uri uri) async {
    try {
      final response = await _client
          .post(uri)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const CommandResult(true);
      }
      return CommandResult(false, 'The Roku answered ${response.statusCode}.');
    } catch (_) {
      return const CommandResult(false, 'Could not reach this Roku.');
    }
  }

  @override
  Future<void> close() async {
    if (_ownsClient) _client.close();
    await _updates.close();
  }
}
