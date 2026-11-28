import 'dart:async';

import '../models/farly_device.dart';
import '../models/remote_action.dart';

typedef CredentialSink = void Function(FarlyDevice device);

enum SessionPhase { connecting, waitingForTv, pairing, ready, limited, failed }

class SessionUpdate {
  const SessionUpdate(this.phase, {this.detail});

  final SessionPhase phase;
  final String? detail;
}

/// How a TV can blank its panel while audio or apps keep playing.
enum PictureOffSupport { none, direct, menu }

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

  /// Point this session at a device whose address may have changed.
  void rebind(FarlyDevice device) {}

  bool supports(RemoteAction action) => true;

  /// Whether this TV offers alternate Menu keys to try.
  bool get supportsMenuProbes => false;

  /// Sends one Menu alternative without changing the saved preference.
  Future<CommandResult> sendMenuProbe(String commandId) async {
    return send(RemoteAction.menu);
  }

  /// Whether the phone can type into an on-screen field on this device.
  bool get supportsText => false;

  /// Types [text] into the focused field on the TV (search, PIN, password).
  Future<CommandResult> sendText(String text) async {
    return const CommandResult(false, 'This device cannot take typed text.');
  }

  /// Deletes one character in the focused TV text field.
  Future<CommandResult> textBackspace() async => send(RemoteAction.back);

  /// Submits the focused TV text field.
  Future<CommandResult> textEnter() async => send(RemoteAction.select);

  /// Whether this TV can turn its picture off; [none] hides the control.
  PictureOffSupport get pictureOffSupport => PictureOffSupport.none;

  /// Turns the TV picture off or back on. [menu] TVs only open their options.
  Future<CommandResult> setPictureOff({required bool off}) async {
    return const CommandResult(false, 'This TV cannot turn its picture off.');
  }

  List<AppShortcut> get shortcuts => const [];

  Future<CommandResult> launch(AppShortcut shortcut) async {
    return const CommandResult(false, 'This device cannot launch apps.');
  }

  /// Answers [SessionPhase.pairing] with the code the TV shows.
  Future<CommandResult> submitCode(String code) async {
    return const CommandResult(
      false,
      'This device does not use a pairing code.',
    );
  }

  /// Whether [retry] can run after the session fails.
  bool get canRetry => false;

  Future<void> retry() async {}

  /// Whether the user can wipe saved pairing and ask the TV for a new code.
  bool get canPairAgain => false;

  /// Clears saved credentials and starts a fresh pairing handshake.
  Future<void> pairAgain() async {}
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
  bool get supportsText => preview;

  @override
  Future<CommandResult> sendText(String text) async {
    if (preview) return CommandResult(false, 'Would type “$text”');
    return CommandResult(false, detail);
  }

  @override
  Future<CommandResult> textEnter() async {
    if (preview) return const CommandResult(true);
    return CommandResult(false, detail);
  }

  @override
  bool get supportsMenuProbes => preview;

  @override
  Future<CommandResult> sendMenuProbe(String commandId) async {
    if (preview) return CommandResult(false, 'Would send Menu ($commandId)');
    return CommandResult(false, detail);
  }

  @override
  Future<void> close() => _updates.close();
}
