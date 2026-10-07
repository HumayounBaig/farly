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
      notifyListeners();
    });
    try {
      await session.open();
    } catch (_) {
      phase = SessionPhase.failed;
      detail = 'Farly could not open a connection.';
      notifyListeners();
    }
  }

  Future<void> send(RemoteAction action) async {
    if (phase == SessionPhase.connecting || phase == SessionPhase.failed) {
      if (phase == SessionPhase.connecting) detail = 'Still connecting.';
      notifyListeners();
      return;
    }
    final result = await session.send(action);
    if (result.detail != null) {
      detail = result.detail;
      notifyListeners();
    }
  }

  Future<void> launch(AppShortcut shortcut) async {
    final result = await session.launch(shortcut);
    if (result.detail != null) {
      detail = result.detail;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    session.close();
    super.dispose();
  }
}
