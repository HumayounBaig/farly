import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:volume_button_listener/volume_button_listener.dart';

import '../models/remote_action.dart';

/// Forwards the phone's volume rocker to TV volume while the remote is open.
class PhoneVolumeBridge with WidgetsBindingObserver {
  PhoneVolumeBridge({required this.onAction});

  final ValueChanged<RemoteAction> onAction;

  final _listener = VolumeButtonListener.instance;
  var _active = false;
  Timer? _holdDelay;
  Timer? _repeat;
  VolumeButtonDirection? _held;

  static bool get _isTestBinding {
    final name = WidgetsBinding.instance.runtimeType.toString();
    return name.contains('TestWidgetsFlutterBinding');
  }

  static bool get supported {
    if (kIsWeb || !VolumeButtonListener.supportsVolumeButtonListener) {
      return false;
    }
    if (_isTestBinding) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> start() async {
    if (_active || !supported) return;
    _listener
      ..showVolumeUI = false
      ..suppressRepeatedPressEvents = false;
    try {
      await _listener.addButtonPressedListener(_onPressed);
      await _listener.addButtonReleasedListener(_onReleased);
    } catch (error, stack) {
      debugPrint('PhoneVolumeBridge start failed: $error\n$stack');
      return;
    }
    _active = true;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _clearHold();
    try {
      await _listener.removeButtonPressedListener(_onPressed);
      await _listener.removeButtonReleasedListener(_onReleased);
    } catch (error, stack) {
      debugPrint('PhoneVolumeBridge stop failed: $error\n$stack');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_listener.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _clearHold();
        unawaited(_listener.pause());
    }
  }

  void _onPressed(VolumeButtonDirection direction) {
    _held = direction;
    _emit(direction);
    _holdDelay?.cancel();
    _repeat?.cancel();
    _holdDelay = Timer(const Duration(milliseconds: 280), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 110), (_) {
        final held = _held;
        if (held == null) return;
        _emit(held);
      });
    });
  }

  void _onReleased(VolumeButtonDirection direction) {
    _clearHold();
  }

  void _emit(VolumeButtonDirection direction) {
    HapticFeedback.selectionClick();
    onAction(switch (direction) {
      VolumeButtonDirection.up => RemoteAction.volumeUp,
      VolumeButtonDirection.down => RemoteAction.volumeDown,
    });
  }

  void _clearHold() {
    _holdDelay?.cancel();
    _repeat?.cancel();
    _holdDelay = null;
    _repeat = null;
    _held = null;
  }
}
