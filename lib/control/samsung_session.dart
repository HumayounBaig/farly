import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../models/farly_device.dart';
import '../models/menu_command.dart';
import '../models/remote_action.dart';
import 'remote_session.dart';
import 'samsung_keys.dart';

class SamsungSession extends RemoteSession {
  SamsungSession({required this.device, this.onCredentials});

  FarlyDevice device;
  final CredentialSink? onCredentials;
  final _updates = SessionUpdates();
  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  void rebind(FarlyDevice device) => this.device = device;

  @override
  bool supports(RemoteAction action) => samsungKey(action) != null;

  @override
  bool get supportsText => true;

  @override
  Future<void> open() async {
    final host = device.host;
    if (host == null) {
      _updates.add(
        const SessionUpdate(
          SessionPhase.failed,
          detail: 'This Samsung TV has no address.',
        ),
      );
      return;
    }

    IOWebSocketChannel? channel;
    for (final secure in [true, false]) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4)
          ..badCertificateCallback = (cert, peer, port) => peer == host;
        final attempt = IOWebSocketChannel.connect(
          samsungSocketUri(host: host, secure: secure, token: device.token),
          customClient: client,
        );
        await attempt.ready.timeout(const Duration(seconds: 4));
        channel = attempt;
        break;
      } catch (_) {
        continue;
      }
    }

    if (channel == null) {
      _updates.add(
        const SessionUpdate(
          SessionPhase.failed,
          detail: 'Could not reach this Samsung TV.',
        ),
      );
      return;
    }

    _channel = channel;
    _imeActive = false;
    final ready = Completer<void>();
    _subscription = channel.stream.listen(
      (data) {
        final update = _interpret(data);
        if (update != null) {
          _updates.add(update);
          if (!ready.isCompleted) ready.complete();
        }
      },
      onError: (_) {
        _updates.add(
          const SessionUpdate(
            SessionPhase.failed,
            detail: 'The TV closed the connection.',
          ),
        );
        if (!ready.isCompleted) ready.complete();
      },
      onDone: () {
        if (identical(_channel, channel)) {
          _channel = null;
          _updates.add(
            const SessionUpdate(
              SessionPhase.failed,
              detail: 'The TV closed the connection. Tap Try again.',
            ),
          );
        }
        if (!ready.isCompleted) ready.complete();
      },
    );

    await ready.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _updates.add(
          const SessionUpdate(
            SessionPhase.waitingForTv,
            detail: 'If the TV shows a prompt, allow Farly.',
          ),
        );
      },
    );
  }

  SessionUpdate? _interpret(Object? data) {
    if (data is! String) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final event = decoded['event']?.toString() ?? '';
    if (event.contains('imeStart')) _imeActive = true;
    if (event.contains('imeEnd') || event.contains('imeDone')) {
      _imeActive = false;
    }
    final body = decoded['data'];
    if (body is Map && body['token'] is String) {
      final token = body['token'] as String;
      device = device.copyWith(token: token);
      onCredentials?.call(device);
    }
    if (event.contains('unauthorized')) {
      return const SessionUpdate(
        SessionPhase.failed,
        detail: 'The TV denied Farly. Allow the connection on the TV.',
      );
    }
    if (event.contains('connect')) {
      return const SessionUpdate(SessionPhase.ready, detail: 'Connected');
    }
    return null;
  }

  var _imeActive = false;

  @override
  bool get supportsMenuProbes => true;

  @override
  Future<CommandResult> send(RemoteAction action) async {
    final channel = _channel;
    if (channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    final key = action == RemoteAction.menu
        ? samsungMenuKey(MenuCommand.resolvedId(device))
        : samsungKey(action);
    if (key == null) {
      return const CommandResult(false, 'This button is not on this TV.');
    }
    try {
      channel.sink.add(jsonEncode(samsungKeyPayload(key)));
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  @override
  Future<CommandResult> sendMenuProbe(String commandId) async {
    final channel = _channel;
    final key = samsungMenuKey(commandId);
    if (channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    if (key == null) {
      return const CommandResult(false, 'Unknown menu key.');
    }
    try {
      channel.sink.add(jsonEncode(samsungKeyPayload(key)));
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  Future<void> _textLock = Future<void>.value();

  @override
  Future<CommandResult> sendText(String text) {
    // Serialize so two calls can't interleave their per-key presses.
    final run = _textLock.then((_) => _sendText(text));
    _textLock = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<CommandResult> _sendText(String text) async {
    final channel = _channel;
    if (channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    if (text.isEmpty) {
      return const CommandResult(false, 'Nothing to type.');
    }
    // No IME session (e.g. YouTube search): SendInputString is dropped, so
    // press one key per character when every character has a key. KEY_A..Z
    // can't express case, so text with capitals keeps the old path.
    final keys = [
      for (final r in text.runes) samsungCharKey(String.fromCharCode(r)),
    ];
    if (!_imeActive && !keys.contains(null) && text == text.toLowerCase()) {
      try {
        for (final key in keys) {
          channel.sink.add(jsonEncode(samsungKeyPayload(key!)));
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        return const CommandResult(true);
      } catch (_) {
        return const CommandResult(false, 'The text did not reach the TV.');
      }
    }
    try {
      channel.sink.add(jsonEncode(samsungTextPayload(text)));
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The text did not reach the TV.');
    }
  }

  @override
  Future<CommandResult> textBackspace() async {
    final channel = _channel;
    if (channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      channel.sink.add(jsonEncode(samsungKeyPayload('KEY_BACKSPACE')));
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  @override
  Future<CommandResult> textEnter() async {
    final channel = _channel;
    if (channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      channel.sink.add(jsonEncode(samsungKeyPayload('KEY_ENTER')));
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  @override
  bool get canRetry => true;

  @override
  Future<void> retry() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    await open();
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _updates.close();
  }
}
