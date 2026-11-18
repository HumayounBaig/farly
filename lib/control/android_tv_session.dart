import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/farly_device.dart';
import '../models/menu_command.dart';
import '../models/remote_action.dart';
import '../models/stream_app.dart';
import 'atv_identity.dart';
import 'atv_wire.dart';
import 'remote_session.dart';

typedef AtvIdentityFactory = Future<AtvIdentity> Function();

Future<AtvIdentity> _freshIdentity() => Isolate.run(createAtvIdentity);

/// Drives Google TV and Android TV sets, including TCL, Hisense, Sony, and
/// Chromecast with Google TV, over the Android TV Remote protocol v2.
///
/// The first connection pairs: the TV shows a six-character code, and the
/// client certificate it then trusts is kept in [FarlyDevice.token] (the
/// certificate) and [FarlyDevice.clientKey] (its private key).
class AndroidTvSession extends RemoteSession {
  AndroidTvSession({
    required this.device,
    this.onCredentials,
    this.pairingPort = atvPairingPort,
    this.remotePort = atvRemotePort,
    AtvIdentityFactory? identities,
    this.timeout = const Duration(seconds: 5),
  }) : _identities = identities ?? _freshIdentity;

  FarlyDevice device;
  final CredentialSink? onCredentials;
  final int pairingPort;
  final int remotePort;
  final Duration timeout;
  final AtvIdentityFactory _identities;
  final _updates = SessionUpdates();

  AtvIdentity? _identity;
  _AtvLink? _pairing;
  Uint8List? _serverCertificate;
  _AtvLink? _remote;
  var _closed = false;
  var _imeCounter = 0;
  var _imeFieldCounter = 0;
  var _hasImeCounter = false;
  var _hasImeFieldCounter = false;
  var _textFieldFocused = false;
  var _textValue = '';
  Completer<bool>? _editEcho;
  var _editEchoFromFieldStatus = false;

  static final apps = [
    StreamApp.netflix.shortcutFor(DeviceBrand.androidTv),
    StreamApp.youtube.shortcutFor(DeviceBrand.androidTv),
  ];

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  List<AppShortcut> get shortcuts => apps;

  @override
  bool get canRetry => true;

  @override
  Future<void> open() async {
    await _resetLinks();

    final host = device.host;
    if (host == null) {
      _say(SessionPhase.failed, 'This TV has no address.');
      return;
    }
    _say(SessionPhase.connecting, 'Connecting');

    final cert = device.token;
    final key = device.clientKey;
    if (cert != null && key != null && cert.isNotEmpty && key.isNotEmpty) {
      _identity = AtvIdentity(certificatePem: cert, privateKeyPem: key);
      if (await _connectRemote(host)) return;
      // Keep the saved cert. A sleepy TV, wrong band, or brief timeout must
      // not mint a new identity and force another pairing code.
      _say(
        SessionPhase.failed,
        'Could not reconnect. Tap Try again, or Pair again if the TV forgot Farly.',
      );
      return;
    }
    await _startPairing(host);
  }

  @override
  void rebind(FarlyDevice device) => this.device = device;

  @override
  Future<void> retry() => open();

  @override
  bool get canPairAgain => true;

  @override
  Future<void> pairAgain() async {
    await _resetLinks();
    _identity = null;
    device = device.copyWith(clearToken: true, clearClientKey: true);
    onCredentials?.call(device);
    final host = device.host;
    if (host == null) {
      _say(SessionPhase.failed, 'This TV has no address.');
      return;
    }
    _say(SessionPhase.connecting, 'Asking the TV for a new code');
    await _startPairing(host);
  }

  Future<void> _resetLinks() async {
    await _pairing?.close();
    await _remote?.close();
    _pairing = null;
    _remote = null;
    _imeCounter = 0;
    _imeFieldCounter = 0;
    _hasImeCounter = false;
    _hasImeFieldCounter = false;
    _textFieldFocused = false;
    _textValue = '';
    _editEcho = null;
    _editEchoFromFieldStatus = false;
  }

  Future<bool> _connectRemote(String host) async {
    final identity = _identity;
    if (identity == null) return false;
    final link = await _AtvLink.connect(host, remotePort, identity, timeout);
    if (link == null) return false;

    // The TV only sends its configuration to a client it has paired with.
    final configured = Completer<bool>();
    final started = Completer<bool>();
    var active = atvFeatures;
    link.listen(
      (frame) {
        final AtvRemoteEvent event;
        try {
          event = parseAtvRemote(frame);
        } catch (_) {
          return;
        }
        switch (event) {
          case AtvConfigureEvent(:final features):
            active = features & atvFeatures;
            link.send(atvConfigure(active));
            if (!configured.isCompleted) configured.complete(true);
          case AtvSetActiveEvent():
            link.send(atvSetActive(active));
          case AtvStartEvent():
            if (!started.isCompleted) started.complete(true);
          case AtvPingEvent(:final value):
            link.send(atvPingResponse(value));
          case AtvImeFocusEvent(
            :final imeCounter,
            :final fieldCounter,
            :final fromKeyInject,
            :final fieldValue,
            :final hasFieldStatus,
          ):
            // Live counters only arrive on remote_ime_key_inject. Batch-edit
            // echoes often carry a stale placeholder and must not win.
            if (fromKeyInject || imeCounter != 0) {
              _imeCounter = imeCounter;
              _hasImeCounter = true;
            }
            if (hasFieldStatus) {
              if (fieldCounter != 0 || fromKeyInject) {
                _imeFieldCounter = fieldCounter;
                _hasImeFieldCounter = true;
              }
              _textFieldFocused = true;
              _textValue = fieldValue;
              _completeEditEcho(fromFieldStatus: true);
            } else if (fromKeyInject) {
              // App changed without a text field — drop stale focus/counters.
              _textFieldFocused = false;
              _textValue = '';
              _hasImeCounter = false;
              _hasImeFieldCounter = false;
            }
          case AtvImeBatchEchoEvent(:final imeCounter, :final fieldCounter):
            if (!_hasImeCounter && imeCounter != 0) {
              _imeCounter = imeCounter;
              _hasImeCounter = true;
            }
            if (!_hasImeFieldCounter && fieldCounter != 0) {
              _imeFieldCounter = fieldCounter;
              _hasImeFieldCounter = true;
            }
            // Soft ack only; field-status inject is the authoritative contents.
            if (imeCounter != 0 || fieldCounter != 0) {
              _completeEditEcho(fromFieldStatus: false);
            }
          case AtvErrorEvent():
          case AtvOtherEvent():
            break;
        }
      },
      onDone: () {
        if (!configured.isCompleted) configured.complete(false);
        if (!started.isCompleted) started.complete(false);
        if (identical(_remote, link) && !_closed) {
          _remote = null;
          _say(
            SessionPhase.failed,
            'The TV closed the connection. Tap Try again.',
          );
        }
      },
    );

    final ok =
        await configured.future.timeout(timeout, onTimeout: () => false) &&
        await started.future.timeout(timeout, onTimeout: () => true);
    if (!ok) {
      await link.close();
      return false;
    }
    _remote = link;
    _say(SessionPhase.ready, 'Connected');
    return true;
  }

  Future<void> _startPairing(String host) async {
    _say(SessionPhase.connecting, 'Asking the TV for a code');
    try {
      // Always mint when identity was cleared after a failed remote reconnect;
      // otherwise reuse a cert already created for this open().
      _identity ??= await _identities();
    } catch (_) {
      _say(SessionPhase.failed, 'Could not prepare a pairing key.');
      return;
    }
    final link = await _AtvLink.connect(host, pairingPort, _identity!, timeout);
    if (link == null) {
      _say(
        SessionPhase.failed,
        'TV did not answer pairing. On Google TV open Remotes & accessories, '
        'allow network remotes, then try again.',
      );
      return;
    }
    _pairing = link;
    _serverCertificate = link.peerCertificate;
    link.listen(link.inbox.add, onDone: link.inbox.close);

    final steps = [
      (atvPairingRequest('Farly'), AtvPairingStep.requestAck),
      (atvPairingOption(), AtvPairingStep.option),
      (atvPairingConfiguration(), AtvPairingStep.configurationAck),
    ];
    for (final (message, expected) in steps) {
      final reply = await _exchange(link, message);
      if (reply == null || !reply.ok || reply.step != expected) {
        await link.close();
        _pairing = null;
        _say(
          SessionPhase.failed,
          'The TV turned down pairing. Check Remotes & accessories, then try again.',
        );
        return;
      }
    }
    _say(
      SessionPhase.pairing,
      'Enter the code on the TV. If none appears, open Remotes & accessories.',
    );
  }

  Future<AtvPairingReply?> _exchange(_AtvLink link, Uint8List message) async {
    link.send(message);
    final frame = await link.inbox.next(const Duration(seconds: 10));
    if (frame == null) return null;
    try {
      return parseAtvPairing(frame);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CommandResult> submitCode(String code) async {
    final link = _pairing;
    final identity = _identity;
    final server = _serverCertificate;
    final host = device.host;
    if (link == null || identity == null || server == null || host == null) {
      return const CommandResult(false, 'Pairing ended. Tap Try again.');
    }
    if (normalizeAtvCode(code) == null) {
      return const CommandResult(
        false,
        'Enter the 6 characters shown on the TV.',
      );
    }
    final secret = atvPairingSecret(
      clientCertificateDer: identity.certificateDer,
      serverCertificateDer: server,
      code: code,
    );
    if (secret == null) {
      return const CommandResult(
        false,
        'That code does not match. Check the TV.',
      );
    }

    final reply = await _exchange(link, atvSecretMessage(secret));
    await link.close();
    _pairing = null;
    if (reply == null || !reply.ok || reply.step != AtvPairingStep.secretAck) {
      _say(
        SessionPhase.failed,
        'The TV did not accept the code. Tap Try again.',
      );
      return const CommandResult(false);
    }

    device = device.copyWith(
      token: identity.certificatePem,
      clientKey: identity.privateKeyPem,
    );
    onCredentials?.call(device);
    _say(SessionPhase.connecting, 'Paired. Connecting');
    if (!await _connectRemote(host)) {
      _say(
        SessionPhase.failed,
        'Paired, but the TV did not open the remote. Tap Try again.',
      );
      return const CommandResult(false);
    }
    return const CommandResult(true);
  }

  @override
  bool get supportsText => true;

  @override
  bool get supportsMenuProbes => true;

  /// Android / Google TV (including TCL) do not honor phone brightness
  /// keycodes — those only dim the set's own panel UI, not picture output.
  @override
  bool supports(RemoteAction action) {
    return switch (action) {
      RemoteAction.brightnessUp || RemoteAction.brightnessDown => false,
      _ => true,
    };
  }

  @override
  Future<CommandResult> send(RemoteAction action) async {
    final link = _remote;
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    final code = action == RemoteAction.menu
        ? atvMenuKeyCode(MenuCommand.resolvedId(device))
        : atvKeyCode(action);
    if (code == null) {
      return const CommandResult(false, 'This button is not on this TV.');
    }
    return link.send(atvKeyInject(code))
        ? const CommandResult(true)
        : const CommandResult(false, 'The key did not reach the TV.');
  }

  @override
  Future<CommandResult> sendMenuProbe(String commandId) async {
    final link = _remote;
    final code = atvMenuKeyCode(commandId);
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    if (code == null) {
      return const CommandResult(false, 'Unknown menu key.');
    }
    return link.send(atvKeyInject(code))
        ? const CommandResult(true)
        : const CommandResult(false, 'The key did not reach the TV.');
  }

  @override
  Future<CommandResult> sendText(String text) async {
    final link = _remote;
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    if (text.isEmpty) {
      return const CommandResult(false, 'Nothing to type.');
    }

    // Prefer the TV input-method path only while a field is focused.
    // On-screen keyboards swallow key events; PS5/Xbox keyboards never report
    // an Android text field.
    if (_textFieldFocused) {
      final start = _textValue.length;
      final pending = Completer<bool>();
      _editEcho = pending;
      _editEchoFromFieldStatus = false;
      final ok = link.send(
        atvImeBatchEdit(
          imeCounter: _imeCounter,
          fieldCounter: _imeFieldCounter,
          text: text,
          start: start,
          end: start,
        ),
      );
      if (!ok) {
        _editEcho = null;
        return const CommandResult(false, 'The text did not reach the TV.');
      }
      final accepted = await pending.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => false,
      );
      final fromField = _editEchoFromFieldStatus;
      if (identical(_editEcho, pending)) _editEcho = null;
      if (accepted) {
        // Field-status ack already set _textValue from the TV.
        if (!fromField) _textValue = '$_textValue$text';
        return const CommandResult(true);
      }
    }

    final asKeys = await _sendTextAsKeys(text);
    if (asKeys.ok) return asKeys;

    return CommandResult(
      false,
      _textFieldFocused
          ? 'The TV did not accept the text. Hide its on-screen keyboard, tap the text box, and try again.'
          : 'No TV text box is focused. Farly can type into TV apps, but not into a PS5 or other console keyboard — use the console controller, or open the field in a TV app first.',
    );
  }

  void _completeEditEcho({required bool fromFieldStatus}) {
    if (fromFieldStatus) _editEchoFromFieldStatus = true;
    final pending = _editEcho;
    if (pending != null && !pending.isCompleted) {
      pending.complete(true);
    }
  }

  Future<CommandResult> _sendTextAsKeys(String text) async {
    final link = _remote;
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final code = atvCharKeyCode(character);
      if (code == null) {
        return CommandResult(
          false,
          'Cannot type “$character” as a key. Focus a TV text box so Farly can use the input method.',
        );
      }
      if (!link.send(atvKeyInject(code))) {
        return const CommandResult(false, 'The text did not reach the TV.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
    if (_textFieldFocused) _textValue = '$_textValue$text';
    return const CommandResult(true);
  }

  @override
  Future<CommandResult> textBackspace() async {
    final link = _remote;
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    final ok = link.send(atvKeyInject(atvKeyDelete));
    if (!ok) {
      return const CommandResult(false, 'The key did not reach the TV.');
    }
    if (_textValue.isNotEmpty) {
      _textValue = _textValue.substring(0, _textValue.length - 1);
    }
    return const CommandResult(true);
  }

  @override
  Future<CommandResult> textEnter() async {
    final link = _remote;
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    return link.send(atvKeyInject(atvKeyEnter))
        ? const CommandResult(true)
        : const CommandResult(false, 'The key did not reach the TV.');
  }

  @override
  Future<CommandResult> launch(AppShortcut shortcut) async {
    final link = _remote;
    if (link == null) {
      return const CommandResult(false, 'The TV is not connected.');
    }
    return link.send(atvAppLink(shortcut.id))
        ? const CommandResult(true)
        : CommandResult(false, 'The TV did not open ${shortcut.label}.');
  }

  void _say(SessionPhase phase, String detail) {
    if (!_closed) _updates.add(SessionUpdate(phase, detail: detail));
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _pairing?.close();
    await _remote?.close();
    await _updates.close();
  }
}

/// One TLS connection that speaks varint-framed protobuf.
class _AtvLink {
  _AtvLink(this._socket);

  final SecureSocket _socket;
  final _reader = AtvFrameReader();
  final inbox = _Inbox();
  StreamSubscription<Uint8List>? _subscription;

  Uint8List? get peerCertificate => _socket.peerCertificate?.der;

  static Future<_AtvLink?> connect(
    String host,
    int port,
    AtvIdentity identity,
    Duration timeout,
  ) async {
    try {
      final context = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(identity.certificatePem.codeUnits)
        ..usePrivateKeyBytes(identity.privateKeyPem.codeUnits);
      final socket = await SecureSocket.connect(
        host,
        port,
        context: context,
        onBadCertificate: (_) => true,
        timeout: timeout,
      );
      return _AtvLink(socket);
    } catch (_) {
      return null;
    }
  }

  void listen(
    void Function(Uint8List frame) onFrame, {
    void Function()? onDone,
  }) {
    _subscription = _socket.listen(
      (chunk) {
        for (final frame in _reader.add(chunk)) {
          onFrame(frame);
        }
      },
      onError: (_) => onDone?.call(),
      onDone: onDone,
      cancelOnError: true,
    );
  }

  bool send(Uint8List message) {
    try {
      _socket.add(atvFrame(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    await _subscription?.cancel();
    try {
      await _socket.close();
    } catch (_) {
      // Already closed by the TV.
    }
    _socket.destroy();
  }
}

class _Inbox {
  final _frames = <Uint8List>[];
  Completer<Uint8List?>? _waiting;
  var _closed = false;

  void add(Uint8List frame) {
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) {
      _waiting = null;
      waiting.complete(frame);
    } else {
      _frames.add(frame);
    }
  }

  void close() {
    _closed = true;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(null);
  }

  Future<Uint8List?> next(Duration timeout) {
    if (_frames.isNotEmpty) return Future.value(_frames.removeAt(0));
    if (_closed) return Future.value(null);
    final waiting = Completer<Uint8List?>();
    _waiting = waiting;
    return waiting.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_waiting, waiting)) _waiting = null;
        return null;
      },
    );
  }
}
