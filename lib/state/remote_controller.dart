import 'dart:async';

import 'package:flutter/foundation.dart';

import '../control/remote_session.dart';
import '../control/session_factory.dart';
import '../models/farly_device.dart';
import '../models/remote_action.dart';

typedef SessionBuilder = RemoteSession Function(
  FarlyDevice device,
  CredentialSink onCredentials,
);

/// Finds the same TV again after its address changed (band or AP hop).
typedef DeviceRelocator = Future<FarlyDevice?> Function(FarlyDevice device);

class RemoteController extends ChangeNotifier {
  RemoteController({
    required FarlyDevice device,
    required CredentialSink onCredentials,
    SessionBuilder? sessions,
    this.relocate,
  }) : _device = device,
       _onCredentials = onCredentials,
       session = (sessions ?? buildSession)(device, onCredentials);

  final RemoteSession session;
  final CredentialSink _onCredentials;
  final DeviceRelocator? relocate;

  FarlyDevice _device;
  FarlyDevice get device => _device;

  SessionPhase phase = SessionPhase.connecting;
  String? detail;
  StreamSubscription<SessionUpdate>? _subscription;
  var _opening = false;
  var _recoveryUsed = false;
  var _wasReady = false;

  Future<void> connect() async {
    _subscription = session.updates.listen((update) {
      phase = update.phase;
      detail = update.detail;
      if (update.phase == SessionPhase.ready) {
        _wasReady = true;
        _recoveryUsed = false;
      }
      _notify();
      if (!_opening &&
          _wasReady &&
          !_recoveryUsed &&
          update.phase == SessionPhase.failed &&
          !_disposed) {
        unawaited(_recoverAfterDrop());
      }
    });
    await _openAcrossHosts(allowRelocate: true);
  }

  Future<void> _recoverAfterDrop() async {
    if (_disposed || _recoveryUsed || _opening) return;
    _recoveryUsed = true;
    detail = 'Connection dropped. Finding this TV again…';
    _notify();
    await _openAcrossHosts(allowRelocate: true);
  }

  Future<void> _openAcrossHosts({required bool allowRelocate}) async {
    if (_opening) return;
    _opening = true;
    try {
      final tried = <String>{};
      final candidates = _device.candidateHosts;
      if (candidates.isEmpty) {
        // Preview and other host-less sessions still need a single open.
        phase = SessionPhase.connecting;
        detail ??= 'Connecting';
        _notify();
        try {
          await session.open();
        } catch (_) {
          phase = SessionPhase.failed;
          detail = 'Could not open a connection.';
          _notify();
        }
        return;
      }
      for (var i = 0; i < candidates.length; i++) {
        if (_disposed) return;
        final host = candidates[i];
        if (!tried.add(host)) continue;
        if (i > 0) {
          detail = 'Trying another address for this TV…';
          _notify();
        }
        await _bindAndOpen(host);
        if (_usable(phase)) {
          _onCredentials(_device);
          return;
        }
      }

      if (!allowRelocate || relocate == null || _disposed) return;
      detail = 'Looking for this TV on your Wi-Fi…';
      _notify();
      final found = await relocate!(_device);
      if (_disposed || found?.host == null) return;
      if (tried.contains(found!.host)) return;
      await _bindAndOpen(found.host!);
      if (_usable(phase)) {
        _device = found.copyWith(
          hosts: mergeHostHistory(
            primary: found.host,
            newer: found.candidateHosts,
            older: tried.toList(),
          ),
        );
        session.rebind(_device);
        _onCredentials(_device);
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _bindAndOpen(String host) async {
    // Keep [id] stable across hops so updateDevice replaces the saved row
    // instead of appending a second paired copy when the TV has no uid.
    final next = _device.copyWith(
      host: host,
      hosts: mergeHostHistory(primary: host, newer: _device.candidateHosts),
    );
    _device = next;
    session.rebind(next);
    phase = SessionPhase.connecting;
    detail ??= 'Connecting';
    _notify();
    try {
      await session.open();
    } catch (_) {
      phase = SessionPhase.failed;
      detail = 'Could not open a connection.';
      _notify();
    }
  }

  static bool _usable(SessionPhase phase) {
    return phase == SessionPhase.ready ||
        phase == SessionPhase.pairing ||
        phase == SessionPhase.waitingForTv ||
        phase == SessionPhase.limited;
  }

  /// TV menu levels the user opened and has not backed out of: Menu pushes,
  /// Back pops, Home or opening an app clears. Moving and selecting inside the
  /// menu leaves it alone.
  int _menuDepth = 0;

  /// On leaving the pad, backs out of any TV menu still open; does nothing
  /// otherwise, so a playing video is left alone.
  Future<void> sendAutoBack() async {
    // shortcut: capped at 5 so a confused count can't spam Back.
    for (var i = 0; i < 5 && _menuDepth > 0 && !_disposed; i++) {
      await send(RemoteAction.back);
    }
    if (!_disposed) _menuDepth = 0;
  }

  Future<void> send(RemoteAction action) async {
    if (_disposed) return;
    if (!_readyForKeys(pairingMessage: 'Enter the code shown on the TV first.')) {
      return;
    }
    _menuDepth = switch (action) {
      RemoteAction.menu => _menuDepth + 1,
      RemoteAction.back => _menuDepth > 0 ? _menuDepth - 1 : 0,
      RemoteAction.home => 0,
      _ => _menuDepth,
    };
    final result = await session.send(action);
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  /// Tries an alternate Menu key without saving it yet.
  Future<void> sendMenuProbe(String commandId) async {
    if (!_readyForKeys(pairingMessage: 'Enter the code shown on the TV first.')) {
      return;
    }
    _menuDepth += 1;
    final result = await session.sendMenuProbe(commandId);
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  /// Remembers which Menu key this TV should use.
  void setMenuCommand(String commandId) {
    _device = _device.copyWith(menuCommand: commandId);
    session.rebind(_device);
    _onCredentials(_device);
    detail = 'Menu key saved for this TV.';
    _notify();
  }

  bool _readyForKeys({required String pairingMessage}) {
    if (phase == SessionPhase.connecting || phase == SessionPhase.failed) {
      if (phase == SessionPhase.connecting) detail = 'Still connecting.';
      _notify();
      return false;
    }
    if (phase == SessionPhase.pairing) {
      detail = pairingMessage;
      _notify();
      return false;
    }
    return true;
  }

  bool submitting = false;

  /// Returns true once the TV accepted the code.
  Future<bool> submitCode(String code) async {
    if (submitting) return false;
    submitting = true;
    _notify();
    try {
      final result = await session.submitCode(code);
      if (result.detail != null) detail = result.detail;
      return result.ok;
    } finally {
      submitting = false;
      _notify();
    }
  }

  Future<void> retry() async {
    _recoveryUsed = false;
    await _openAcrossHosts(allowRelocate: true);
  }

  bool get canPairAgain => session.canPairAgain;

  /// Wipes the saved pairing and asks the TV for a fresh code.
  Future<void> pairAgain() async {
    if (!session.canPairAgain || _opening) return;
    _recoveryUsed = false;
    _opening = true;
    try {
      _device = _device.copyWith(clearToken: true, clearClientKey: true);
      session.rebind(_device);
      await session.pairAgain();
    } finally {
      _opening = false;
    }
  }

  Future<void> launch(AppShortcut shortcut) async {
    if (phase != SessionPhase.ready && phase != SessionPhase.limited) {
      detail = phase == SessionPhase.pairing
          ? 'Enter the code shown on the TV first.'
          : 'The TV is not connected.';
      _notify();
      return;
    }
    _menuDepth = 0; // an opened app, not a menu, is on screen
    final result = await session.launch(shortcut);
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  Future<void> sendText(String text) async {
    if (!_readyForText) return;
    final result = await _inOrder(() => session.sendText(text));
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  Future<void> textBackspace() async {
    if (!_readyForText) return;
    final result = await _inOrder(() => session.textBackspace());
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  Future<void> textEnter() async {
    if (!_readyForText) return;
    final result = await _inOrder(() => session.textEnter());
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  /// Text edits run one at a time, in order: an overlapping send could make a
  /// TV apply the same text twice or build on a stale field value.
  Future<void> _textQueue = Future<void>.value();

  Future<CommandResult> _inOrder(Future<CommandResult> Function() edit) {
    final run = _textQueue.then((_) => edit());
    _textQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  bool get _readyForText {
    if (phase != SessionPhase.ready && phase != SessionPhase.limited) {
      detail = phase == SessionPhase.pairing
          ? 'Enter the code shown on the TV first.'
          : 'The TV is not connected.';
      _notify();
      return false;
    }
    if (!session.supportsText) {
      detail = 'This TV cannot take typed text yet.';
      _notify();
      return false;
    }
    return true;
  }

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    session.close();
    super.dispose();
  }
}
