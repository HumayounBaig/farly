import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../models/farly_device.dart';
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
  bool supports(RemoteAction action) => samsungKey(action) != null;

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
          detail: 'Farly could not reach this Samsung TV.',
        ),
      );
      return;
    }

    _channel = channel;
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
    final decoded = jsonDecode(data);
    if (decoded is! Map) return null;
    final event = decoded['event']?.toString() ?? '';
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

  @override
  Future<CommandResult> send(RemoteAction action) async {
    final key = samsungKey(action);
    final channel = _channel;
    if (key == null || channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      channel.sink.add(jsonEncode(samsungKeyPayload(key)));
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _updates.close();
  }
}
