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
          detail = 'Farly could not open a connection.';
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
      detail = 'Farly could not open a connection.';
      _notify();
    }
  }

  static bool _usable(SessionPhase phase) {
    return phase == SessionPhase.ready ||
        phase == SessionPhase.pairing ||
        phase == SessionPhase.waitingForTv ||
        phase == SessionPhase.limited;
  }

  Future<void> send(RemoteAction action) async {
    if (phase == SessionPhase.connecting || phase == SessionPhase.failed) {
      if (phase == SessionPhase.connecting) detail = 'Still connecting.';
      _notify();
      return;
    }
    if (phase == SessionPhase.pairing) {
      detail = 'Enter the code shown on the TV first.';
      _notify();
      return;
    }
    final result = await session.send(action);
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
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

  Future<void> launch(AppShortcut shortcut) async {
    if (phase != SessionPhase.ready && phase != SessionPhase.limited) {
      detail = phase == SessionPhase.pairing
          ? 'Enter the code shown on the TV first.'
          : 'The TV is not connected.';
      _notify();
      return;
    }
    final result = await session.launch(shortcut);
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  Future<void> sendText(String text) async {
    if (!_readyForText) return;
    final result = await session.sendText(text);
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  Future<void> textBackspace() async {
    if (!_readyForText) return;
    final result = await session.textBackspace();
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
  }

  Future<void> textEnter() async {
    if (!_readyForText) return;
    final result = await session.textEnter();
    if (result.detail != null) {
      detail = result.detail;
      _notify();
    }
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
