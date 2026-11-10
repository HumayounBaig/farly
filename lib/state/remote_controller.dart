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

class RemoteController extends ChangeNotifier {
  RemoteController({
    required FarlyDevice device,
    required CredentialSink onCredentials,
    SessionBuilder? sessions,
  }) : session = (sessions ?? buildSession)(device, onCredentials);

  final RemoteSession session;
  SessionPhase phase = SessionPhase.connecting;
  String? detail;
  StreamSubscription<SessionUpdate>? _subscription;

  Future<void> connect() async {
    _subscription = session.updates.listen((update) {
      phase = update.phase;
      detail = update.detail;
      _notify();
    });
    try {
      await session.open();
    } catch (_) {
      phase = SessionPhase.failed;
      detail = 'Farly could not open a connection.';
      _notify();
    }
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

  Future<void> retry() => session.retry();

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
