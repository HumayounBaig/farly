import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.label,
    this.dimWhenDisabled = true,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Replaces the child's own semantics when set.
  final String? label;
  final bool dimWhenDisabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _setDown(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: widget.label != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setDown(true) : null,
        onTapUp: enabled ? (_) => _setDown(false) : null,
        onTapCancel: enabled ? () => _setDown(false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled || !widget.dimWhenDisabled ? 1 : 0.5,
            duration: const Duration(milliseconds: 150),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class KeyFace extends StatelessWidget {
  const KeyFace({
    super.key,
    required this.icon,
    this.size = 56,
    this.tint = FarlyColors.bone,
    this.accent = false,
  });

  final IconData icon;
  final double size;
  final Color tint;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: accent ? FarlySurfaces.sunDisc() : FarlySurfaces.glassDisc,
      child: Icon(
        icon,
        size: size * 0.42,
        color: accent ? FarlyColors.night : tint,
      ),
    );
  }
}

class RoundKey extends StatelessWidget {
  const RoundKey({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 56,
    this.tint = FarlyColors.bone,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color tint;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      label: label,
      onPressed: onPressed,
      child: KeyFace(icon: icon, size: size, tint: tint, accent: accent),
    );
  }
}

class RockerSegment {
  const RockerSegment({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.id,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Key? id;
}

class KeyRocker extends StatelessWidget {
  const KeyRocker({super.key, required this.segments, this.height = 58});

  final List<RockerSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: FarlySurfaces.glass(radius: height / 2),
      child: Row(
        children: [
          for (var index = 0; index < segments.length; index++) ...[
            if (index > 0)
              Container(
                width: 1,
                height: height * 0.42,
                color: const Color(0x22FFFFFF),
              ),
            Expanded(
              child: Pressable(
                key: segments[index].id,
                label: segments[index].label,
                onPressed: segments[index].onPressed,
                child: SizedBox.expand(
                  child: Icon(
                    segments[index].icon,
                    size: 24,
                    color: FarlyColors.bone,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
