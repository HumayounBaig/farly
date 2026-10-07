import 'dart:async';

import '../models/farly_device.dart';
import '../models/remote_action.dart';

typedef CredentialSink = void Function(FarlyDevice device);

enum SessionPhase { connecting, waitingForTv, ready, limited, failed }

class SessionUpdate {
  const SessionUpdate(this.phase, {this.detail});

  final SessionPhase phase;
  final String? detail;
}

class CommandResult {
  const CommandResult(this.ok, [this.detail]);

  final bool ok;
  final String? detail;
}

class SessionUpdates {
  final _controller = StreamController<SessionUpdate>.broadcast();

  Stream<SessionUpdate> get stream => _controller.stream;

  void add(SessionUpdate update) {
    if (!_controller.isClosed) _controller.add(update);
  }

  Future<void> close() => _controller.close();
}

abstract class RemoteSession {
  Stream<SessionUpdate> get updates;

  Future<void> open();

  Future<CommandResult> send(RemoteAction action);

  Future<void> close();

  bool supports(RemoteAction action) => true;

  List<AppShortcut> get shortcuts => const [];

  Future<CommandResult> launch(AppShortcut shortcut) async {
    return const CommandResult(false, 'This device cannot launch apps.');
  }
}

/// A session that explains itself instead of pretending to control a device.
class NotedSession extends RemoteSession {
  NotedSession({
    required this.phase,
    required this.detail,
    this.preview = false,
  });

  final SessionPhase phase;
  final String detail;
  final bool preview;
  final _updates = SessionUpdates();

  @override
  Stream<SessionUpdate> get updates => _updates.stream;

  @override
  Future<void> open() async {
    _updates.add(SessionUpdate(phase, detail: detail));
  }

  @override
  Future<CommandResult> send(RemoteAction action) async {
    if (preview) return CommandResult(false, 'Would send ${action.label}');
    return CommandResult(false, detail);
  }

  @override
  Future<void> close() => _updates.close();
}
