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
      // excludeSemantics drops the GestureDetector's actions; restore them so
      // screen readers can activate a labelled key.
      onTap: enabled ? widget.onPressed : null,
      onLongPress: widget.onLongPress,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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

/// Thin Control Center–style capsule that fires increase/decrease on drag.
class LevelRail extends StatefulWidget {
  const LevelRail({
    super.key,
    required this.icon,
    required this.label,
    required this.onIncrease,
    required this.onDecrease,
    this.onIconTap,
    this.increaseKey,
    this.decreaseKey,
    this.iconKey,
    this.width = 48,
    this.height = 156,
    /// How many TV volume/brightness ticks one rail step sends.
    this.steps = 1,
  });

  final IconData icon;
  final String label;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback? onIconTap;
  final Key? increaseKey;
  final Key? decreaseKey;
  final Key? iconKey;
  final double width;
  final double height;
  final int steps;

  @override
  State<LevelRail> createState() => _LevelRailState();
}

class _LevelRailState extends State<LevelRail> {
  static const _step = 18.0;
  static const _tapTravel = 10.0;

  var _level = 0.58;
  var _pending = 0.0;
  Offset? _origin;
  DateTime? _lastAt;

  void _bump(bool up) {
    HapticFeedback.selectionClick();
    final count = widget.steps < 1 ? 1 : widget.steps;
    for (var i = 0; i < count; i++) {
      if (up) {
        widget.onIncrease();
      } else {
        widget.onDecrease();
      }
    }
    setState(() {
      final delta = 0.07 * count.clamp(1, 10) / (count > 1 ? 2 : 1);
      _level = (_level + (up ? delta : -delta)).clamp(0.12, 1.0);
    });
  }

  void _drag(double dy) {
    final next = _pending - dy;
    final now = DateTime.now();
    final last = _lastAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 70)) {
      _pending = next;
      return;
    }
    if (next.abs() < _step) {
      _pending = next;
      return;
    }
    _bump(next > 0);
    _pending = 0;
    _lastAt = now;
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.width / 2;
    return Semantics(
      label: widget.label,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Container(
          decoration: FarlySurfaces.glass(radius: radius).copyWith(
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fillHeight = constraints.maxHeight * _level;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOut,
                      height: fillHeight,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            FarlyColors.horizon.withValues(alpha: 0.72),
                            FarlyColors.sunrise.withValues(alpha: 0.28),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _origin = details.localPosition,
                    onTapUp: (details) {
                      final origin = _origin;
                      _origin = null;
                      if (origin == null) return;
                      final travel =
                          (details.localPosition - origin).distance;
                      if (travel >= _tapTravel) return;
                      final up =
                          details.localPosition.dy < constraints.maxHeight / 2;
                      _bump(up);
                    },
                    onTapCancel: () => _origin = null,
                    onVerticalDragStart: (details) {
                      _pending = 0;
                      _lastAt = null;
                      _origin = details.localPosition;
                    },
                    onVerticalDragUpdate: (details) =>
                        _drag(details.delta.dy),
                    onVerticalDragEnd: (_) {
                      _pending = 0;
                      _origin = null;
                    },
                    onVerticalDragCancel: () {
                      _pending = 0;
                      _origin = null;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Icon(
                            key: widget.increaseKey,
                            Icons.add_rounded,
                            size: 14,
                            color: FarlyColors.mist.withValues(alpha: 0.45),
                          ),
                          const Spacer(),
                          if (widget.onIconTap == null)
                            Icon(
                              key: widget.iconKey,
                              widget.icon,
                              size: 22,
                              color: FarlyColors.bone,
                            )
                          else
                            Pressable(
                              key: widget.iconKey,
                              label: '${widget.label}, tap for mute',
                              onPressed: widget.onIconTap,
                              child: Icon(
                                widget.icon,
                                size: 22,
                                color: FarlyColors.bone,
                              ),
                            ),
                          const Spacer(),
                          Icon(
                            key: widget.decreaseKey,
                            Icons.remove_rounded,
                            size: 14,
                            color: FarlyColors.mist.withValues(alpha: 0.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
