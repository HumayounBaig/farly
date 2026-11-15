import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft iOS-style jiggle while the remote is in arrange mode.
///
/// Uses a tiny translation (not rotation) so hit-testing for drag handles
/// stays aligned with what the user sees.
class Jiggle extends StatefulWidget {
  const Jiggle({
    super.key,
    required this.child,
    this.active = true,
  });

  final Widget child;
  final bool active;

  @override
  State<Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<Jiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant Jiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final phase = (widget.key?.hashCode ?? hashCode).abs() % 17 / 17;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value + phase) % 1.0;
        final dx = math.sin(t * math.pi * 2) * 1.2;
        final dy = math.cos(t * math.pi * 2) * 0.8;
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: widget.child,
    );
  }
}
