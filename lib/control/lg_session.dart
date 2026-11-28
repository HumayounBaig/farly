import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../models/farly_device.dart';
import '../models/menu_command.dart';
import '../models/remote_action.dart';
import 'lg_registration.dart';
import 'remote_session.dart';

typedef LgCall = Future<Map<dynamic, dynamic>> Function(
  String uri,
  Map<String, dynamic> payload,
);

/// Turns the panel off or on; tries the webOS 4 service if the first errors.
/// Never use standbyMode "passive": it cannot turn the screen back on.
Future<CommandResult> lgSetScreen(LgCall call, {required bool off}) async {
  final verb = off ? 'turnOffScreen' : 'turnOnScreen';
  for (final base in const [
    'ssap://com.webos.service.tvpower/power/',
    'ssap://com.webos.service.tv.power/',
  ]) {
    final reply = await call('$base$verb', {'standbyMode': 'active'});
    final body = reply['payload'];
    final failed =
        reply['type'] == 'error' || (body is Map && body['returnValue'] == false);
    if (!failed) return const CommandResult(true);
  }
  return const CommandResult(false, 'This TV did not accept Picture off.');
}

class LgSession extends RemoteSession {
  LgSession({required this.device, this.onCredentials});

  FarlyDevice device;
  final CredentialSink? onCredentials;
  final _updates = SessionUpdates();
  IOWebSocketChannel? _channel;
  IOWebSocketChannel? _pointer;
  StreamSubscription<dynamic>? _subscription;
  var _command = 0;
  var _muted = false;
  final _pending = <String, Completer<Map<dynamic, dynamic>>>{};

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  void rebind(FarlyDevice device) => this.device = device;

  @override
  bool supports(RemoteAction action) {
    return switch (action) {
      RemoteAction.power ||
      RemoteAction.volumeUp ||
      RemoteAction.volumeDown ||
      RemoteAction.mute => true,
      _ => lgPointerButton(action) != null,
    };
  }

  @override
  Future<void> open() async {
    final host = device.host;
    if (host == null) {
      _updates.add(
        const SessionUpdate(
          SessionPhase.failed,
          detail: 'This LG TV has no address.',
        ),
      );
      return;
    }

    IOWebSocketChannel? channel;
    for (final secure in [false, true]) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4)
          ..badCertificateCallback = (cert, peer, port) => peer == host;
        final uri = Uri(
          scheme: secure ? 'wss' : 'ws',
          host: host,
          port: secure ? 3001 : 3000,
        );
        final attempt = IOWebSocketChannel.connect(uri, customClient: client);
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
          detail: 'Could not reach this LG TV.',
        ),
      );
      return;
    }

    _channel = channel;
    final settled = Completer<void>();
    _subscription = channel.stream.listen(
      (data) => _onMessage(data, settled),
      onError: (_) {
        _updates.add(
          const SessionUpdate(
            SessionPhase.failed,
            detail: 'The TV closed the connection.',
          ),
        );
        if (!settled.isCompleted) settled.complete();
      },
      onDone: () {
        if (!identical(_channel, channel)) return;
        _channel = null;
        _updates.add(
          const SessionUpdate(
            SessionPhase.failed,
            detail: 'The TV closed the connection. Tap Try again.',
          ),
        );
        if (!settled.isCompleted) settled.complete();
      },
    );
    channel.sink.add(lgRegistrationText(clientKey: device.clientKey));
    await settled.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _updates.add(
          const SessionUpdate(
            SessionPhase.waitingForTv,
            detail: 'Accept Farly on the TV if it is asking.',
          ),
        );
      },
    );
  }

  void _onMessage(Object? data, Completer<void> settled) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final waiting = _pending[decoded['id']];
    if (waiting != null) {
      if (!waiting.isCompleted) waiting.complete(decoded);
      return;
    }
    // A command reply that came after its wait ended must not touch the phase.
    if (decoded['id']?.toString().startsWith('cmd_') ?? false) return;
    final type = decoded['type']?.toString() ?? '';
    final payload = decoded['payload'];
    final body = payload is Map ? payload : const <String, dynamic>{};

    if (body['client-key'] is String) {
      device = device.copyWith(clientKey: body['client-key'] as String);
      onCredentials?.call(device);
      _updates.add(
        const SessionUpdate(SessionPhase.ready, detail: 'Connected'),
      );
      if (!settled.isCompleted) settled.complete();
      _openPointer();
      return;
    }

    if (type == 'registered') {
      _updates.add(
        const SessionUpdate(SessionPhase.ready, detail: 'Connected'),
      );
      if (!settled.isCompleted) settled.complete();
      _openPointer();
      return;
    }

    if (type == 'error') {
      _updates.add(
        const SessionUpdate(
          SessionPhase.failed,
          detail: 'The TV rejected the connection.',
        ),
      );
      if (!settled.isCompleted) settled.complete();
      return;
    }

    final socketPath = body['socketPath'];
    if (socketPath is String && socketPath.isNotEmpty) {
      _connectPointer(socketPath);
      return;
    }

    if (body['pairingType'] != null || type == 'response') {
      _updates.add(
        const SessionUpdate(
          SessionPhase.waitingForTv,
          detail: 'Accept Farly on the TV.',
        ),
      );
    }
  }

  void _openPointer() {
    final channel = _channel;
    if (channel == null) return;
    _command += 1;
    channel.sink.add(
      jsonEncode(
        lgRequest(
          'pointer_$_command',
          'ssap://com.webos.service.networkinput/getPointerInputSocket',
        ),
      ),
    );
  }

  Future<void> _connectPointer(String socketPath) async {
    try {
      final host = device.host;
      final client = HttpClient()
        ..badCertificateCallback = (cert, peer, port) => peer == host;
      final channel = IOWebSocketChannel.connect(
        Uri.parse(socketPath),
        customClient: client,
      );
      await channel.ready.timeout(const Duration(seconds: 4));
      _pointer = channel;
    } catch (_) {
      _pointer = null;
    }
  }

  @override
  bool get supportsText => true;

  @override
  PictureOffSupport get pictureOffSupport => PictureOffSupport.direct;

  @override
  Future<CommandResult> setPictureOff({required bool off}) async {
    if (_channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    return lgSetScreen(_call, off: off);
  }

  Future<Map<dynamic, dynamic>> _call(
    String uri,
    Map<String, dynamic> payload,
  ) {
    _command += 1;
    final id = 'cmd_$_command';
    final done = _pending[id] = Completer<Map<dynamic, dynamic>>();
    _channel?.sink.add(jsonEncode(lgRequest(id, uri, payload)));
    return done.future
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => const {'type': 'error'},
        )
        .whenComplete(() => _pending.remove(id));
  }

  @override
  bool get supportsMenuProbes => true;

  @override
  Future<CommandResult> send(RemoteAction action) async {
    final channel = _channel;
    if (channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      switch (action) {
        case RemoteAction.power:
          _request('ssap://system/turnOff');
        case RemoteAction.volumeUp:
          _request('ssap://audio/volumeUp');
        case RemoteAction.volumeDown:
          _request('ssap://audio/volumeDown');
        case RemoteAction.mute:
          _muted = !_muted;
          _request('ssap://audio/setMute', {'mute': _muted});
        case RemoteAction.menu:
          return await _sendPointer(
            lgMenuButton(MenuCommand.resolvedId(device)),
          );
        default:
          return await _sendPointer(lgPointerButton(action));
      }
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  @override
  Future<CommandResult> sendMenuProbe(String commandId) async {
    if (_channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      return await _sendPointer(lgMenuButton(commandId));
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  Future<CommandResult> _sendPointer(String? button) async {
    final pointer = _pointer;
    if (button == null || pointer == null) {
      return const CommandResult(
        false,
        'The TV has not opened button control yet.',
      );
    }
    pointer.sink.add(lgPointerMessage(button));
    return const CommandResult(true);
  }

  @override
  Future<CommandResult> sendText(String text) async {
    if (_channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    if (text.isEmpty) {
      return const CommandResult(false, 'Nothing to type.');
    }
    try {
      _request('ssap://com.webos.service.ime/insertText', {
        'text': text,
        'replace': false,
      });
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The text did not reach the TV.');
    }
  }

  @override
  Future<CommandResult> textBackspace() async {
    if (_channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      _request('ssap://com.webos.service.ime/deleteCharacters', {'count': 1});
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  @override
  Future<CommandResult> textEnter() async {
    if (_channel == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    try {
      _request('ssap://com.webos.service.ime/sendEnterKey');
      return const CommandResult(true);
    } catch (_) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
  }

  void _request(String uri, [Map<String, dynamic>? payload]) {
    _command += 1;
    _channel?.sink.add(jsonEncode(lgRequest('cmd_$_command', uri, payload)));
  }

  @override
  bool get canRetry => true;

  @override
  Future<void> retry() async {
    await _subscription?.cancel();
    await _pointer?.sink.close();
    await _channel?.sink.close();
    _pointer = null;
    _channel = null;
    await open();
  }

  @override
  Future<void> close() async {
    for (final waiting in _pending.values) {
      if (!waiting.isCompleted) waiting.complete(const {'type': 'error'});
    }
    await _subscription?.cancel();
    await _pointer?.sink.close();
    await _channel?.sink.close();
    await _updates.close();
  }
}
