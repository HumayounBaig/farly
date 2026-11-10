import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/remote_action.dart';
import '../theme/farly_colors.dart';

class HorizonPad extends StatefulWidget {
  const HorizonPad({super.key, required this.onAction, this.height = 280});

  final ValueChanged<RemoteAction> onAction;
  final double height;

  @override
  State<HorizonPad> createState() => _HorizonPadState();
}

class _HorizonPadState extends State<HorizonPad> {
  Offset? _finger;
  Offset _pending = Offset.zero;
  Offset? _panOrigin;
  RemoteAction? _flash;
  RemoteAction? _hover;
  Timer? _flashTimer;
  DateTime? _lastSwipeAt;
  var _pressed = false;

  static const _firstStep = 52.0;
  static const _repeatStep = 46.0;
  static const _axisLock = 1.25;
  static const _repeatGap = Duration(milliseconds: 120);
  static const _tapTravel = 14.0;
  static const _selectHit = 0.23;
  static const _selectDraw = 0.23;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _emit(
    RemoteAction action, {
    required bool select,
    required bool repeat,
  }) {
    if (select) {
      HapticFeedback.mediumImpact();
    } else if (repeat) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.lightImpact();
    }
    widget.onAction(action);
    _flashTimer?.cancel();
    setState(() => _flash = action);
    _flashTimer = Timer(Duration(milliseconds: select ? 260 : 220), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  RemoteAction? _zone(Offset point, Size size) {
    final offset = point - size.center(Offset.zero);
    final short = size.shortestSide;
    if (offset.distance < short * _selectHit) return RemoteAction.select;
    final x = offset.dx / (size.width / 2);
    final y = offset.dy / (size.height / 2);
    // Corners where both axes are strong and close — ignore the tap.
    if (x.abs() > 0.35 &&
        y.abs() > 0.35 &&
        (x.abs() - y.abs()).abs() / math.max(x.abs(), y.abs()) < 0.15) {
      return null;
    }
    if (x.abs() > y.abs()) {
      return x > 0 ? RemoteAction.right : RemoteAction.left;
    }
    return y > 0 ? RemoteAction.down : RemoteAction.up;
  }

  RemoteAction? _hoverZone(Offset point, Size size) {
    final offset = point - size.center(Offset.zero);
    if (offset.distance < size.shortestSide * _selectHit) {
      return RemoteAction.select;
    }
    final x = offset.dx / (size.width / 2);
    final y = offset.dy / (size.height / 2);
    if (x.abs() > y.abs()) {
      return x > 0 ? RemoteAction.right : RemoteAction.left;
    }
    return y > 0 ? RemoteAction.down : RemoteAction.up;
  }

  void _swipe(Offset delta) {
    final next = _pending + delta;
    final now = DateTime.now();
    final last = _lastSwipeAt;
    final repeating = last != null;
    final step = repeating ? _repeatStep : _firstStep;
    if (last != null && now.difference(last) < _repeatGap) {
      _pending = next;
      return;
    }

    RemoteAction? action;
    if (next.dx.abs() >= step && next.dx.abs() >= next.dy.abs() * _axisLock) {
      action = next.dx > 0 ? RemoteAction.right : RemoteAction.left;
    } else if (next.dy.abs() >= step &&
        next.dy.abs() >= next.dx.abs() * _axisLock) {
      action = next.dy > 0 ? RemoteAction.down : RemoteAction.up;
    }

    if (action != null) {
      _emit(action, select: false, repeat: repeating);
      _pending = Offset.zero;
      _lastSwipeAt = now;
    } else {
      _pending = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          return Semantics(
            button: true,
            label: 'Direction pad',
            hint: 'Swipe or tap an edge to move. Tap the center to select.',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                setState(() {
                  _finger = details.localPosition;
                  _hover = _hoverZone(details.localPosition, size);
                  _pressed = true;
                  _panOrigin = details.localPosition;
                });
              },
              onTapUp: (details) {
                final travel = _panOrigin == null
                    ? 0.0
                    : (details.localPosition - _panOrigin!).distance;
                if (travel < _tapTravel) {
                  final action = _zone(details.localPosition, size);
                  if (action != null) {
                    _emit(
                      action,
                      select: action == RemoteAction.select,
                      repeat: false,
                    );
                  }
                }
                setState(() {
                  _finger = null;
                  _hover = null;
                  _pressed = false;
                  _panOrigin = null;
                });
              },
              onTapCancel: () => setState(() {
                _finger = null;
                _hover = null;
                _pressed = false;
                _panOrigin = null;
              }),
              onPanStart: (details) {
                setState(() {
                  _finger = details.localPosition;
                  _hover = _hoverZone(details.localPosition, size);
                  _pending = Offset.zero;
                  _lastSwipeAt = null;
                  _pressed = true;
                  _panOrigin = details.localPosition;
                });
              },
              onPanUpdate: (details) {
                _swipe(details.delta);
                setState(() {
                  _finger = details.localPosition;
                  _hover = _hoverZone(details.localPosition, size);
                });
              },
              onPanEnd: (_) => setState(() {
                _finger = null;
                _hover = null;
                _pressed = false;
                _panOrigin = null;
                _pending = Offset.zero;
              }),
              onPanCancel: () => setState(() {
                _finger = null;
                _hover = null;
                _pressed = false;
                _panOrigin = null;
                _pending = Offset.zero;
              }),
              child: AnimatedScale(
                scale: _pressed ? 0.988 : 1,
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOut,
                child: CustomPaint(
                  size: size,
                  painter: _HorizonPainter(
                    finger: _finger,
                    flash: _flash,
                    hover: _hover,
                    selectRadiusFactor: _selectDraw,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  const _HorizonPainter({
    required this.finger,
    required this.flash,
    required this.hover,
    required this.selectRadiusFactor,
  });

  final Offset? finger;
  final RemoteAction? flash;
  final RemoteAction? hover;
  final double selectRadiusFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(36));
    final center = rect.center;
    final short = size.shortestSide;

    canvas.drawRRect(
      shape.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color(0x73000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF29403A), Color(0xFF111A17)],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(shape);
    final rise = Offset(center.dx, size.height * 1.1);
    final riseRadius = size.width * 0.75;
    canvas.drawCircle(
      rise,
      riseRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            FarlyColors.horizon.withValues(alpha: 0.16),
            FarlyColors.horizon.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: rise, radius: riseRadius)),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = FarlyColors.bone.withValues(alpha: 0.06);
    for (final factor in [0.3, 0.48, 0.68]) {
      canvas.drawCircle(center, short * factor, ring);
    }

    // Soft quadrant guides.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = FarlyColors.bone.withValues(alpha: 0.05);
    canvas.drawLine(
      Offset(center.dx, 18),
      Offset(center.dx, size.height - 18),
      guide,
    );
    canvas.drawLine(
      Offset(18, center.dy),
      Offset(size.width - 18, center.dy),
      guide,
    );

    _wedge(canvas, size, hover, lit: false);
    _wedge(canvas, size, flash, lit: true);

    final touch = finger;
    if (touch != null) {
      final radius = short * 0.34;
      canvas.drawCircle(
        touch,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              FarlyColors.horizon.withValues(alpha: 0.34),
              FarlyColors.horizon.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: touch, radius: radius)),
      );
    }
    canvas.restore();

    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x2EFFFFFF), Color(0x05FFFFFF)],
        ).createShader(rect),
    );

    final selecting = flash == RemoteAction.select;
    final hoveringSelect = hover == RemoteAction.select;
    final selectRadius = short * selectRadiusFactor;
    canvas.drawCircle(
      center,
      selectRadius,
      Paint()
        ..color = FarlyColors.horizon.withValues(
          alpha: selecting
              ? 0.45
              : hoveringSelect
              ? 0.22
              : 0.1,
        ),
    );
    canvas.drawCircle(
      center,
      selectRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = FarlyColors.horizon.withValues(
          alpha: selecting || hoveringSelect ? 1 : 0.55,
        ),
    );
    canvas.drawCircle(center, 4, Paint()..color = FarlyColors.horizon);

    _chevron(canvas, Offset(center.dx, 40), 0, flash == RemoteAction.up);
    _chevron(
      canvas,
      Offset(size.width - 40, center.dy),
      math.pi / 2,
      flash == RemoteAction.right,
    );
    _chevron(
      canvas,
      Offset(center.dx, size.height - 40),
      math.pi,
      flash == RemoteAction.down,
    );
    _chevron(
      canvas,
      Offset(40, center.dy),
      -math.pi / 2,
      flash == RemoteAction.left,
    );
  }

  void _wedge(
    Canvas canvas,
    Size size,
    RemoteAction? action, {
    required bool lit,
  }) {
    if (action == null || action == RemoteAction.select) return;
    final center = size.center(Offset.zero);
    final alpha = lit ? 0.16 : 0.08;
    final paint = Paint()..color = FarlyColors.horizon.withValues(alpha: alpha);
    final path = Path()..moveTo(center.dx, center.dy);
    switch (action) {
      case RemoteAction.up:
        path
          ..lineTo(0, 0)
          ..lineTo(size.width, 0);
      case RemoteAction.down:
        path
          ..lineTo(0, size.height)
          ..lineTo(size.width, size.height);
      case RemoteAction.left:
        path
          ..lineTo(0, 0)
          ..lineTo(0, size.height);
      case RemoteAction.right:
        path
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height);
      default:
        return;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _chevron(Canvas canvas, Offset at, double angle, bool lit) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(-11, 5)
      ..lineTo(0, -6)
      ..lineTo(11, 5);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lit
            ? FarlyColors.horizon
            : FarlyColors.mist.withValues(alpha: 0.55),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HorizonPainter oldDelegate) {
    return oldDelegate.finger != finger ||
        oldDelegate.flash != flash ||
        oldDelegate.hover != hover ||
        oldDelegate.selectRadiusFactor != selectRadiusFactor;
  }
}
