import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';

/// Sun on the horizon with two signal arcs: something far away, answering.
class FarlyMark extends StatelessWidget {
  const FarlyMark({super.key, this.size = 40, this.background = true});

  final double size;
  final bool background;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: FarlyMarkPainter(background: background)),
    );
  }
}

class FarlyMarkPainter extends CustomPainter {
  const FarlyMarkPainter({
    this.background = true,
    this.glyph = true,
    this.rounded = true,
    this.inset = 0,
  });

  final bool background;
  final bool glyph;
  final bool rounded;

  /// Fraction of the side kept empty around the glyph.
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final side = size.shortestSide;
    if (background) {
      canvas.save();
      if (rounded) {
        canvas.clipRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(side * 0.225)),
        );
      }
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF22504A), Color(0xFF0B110F)],
          ).createShader(rect),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, 0.14),
            radius: 0.5,
            colors: [
              FarlyColors.horizon.withValues(alpha: 0.34),
              FarlyColors.horizon.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }
    if (glyph) _paintGlyph(canvas, rect.deflate(side * inset));
  }

  void _paintGlyph(Canvas canvas, Rect area) {
    Offset at(double x, double y) =>
        Offset(area.left + area.width * x, area.top + area.height * y);
    final unit = area.shortestSide;
    const horizonY = 0.58;
    final sunCenter = at(0.5, horizonY);
    final sunRadius = unit * 0.16;

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        area.left - unit,
        area.top - unit,
        area.right + unit,
        sunCenter.dy,
      ),
    );
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [FarlyColors.sunrise, FarlyColors.ember],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius)),
    );
    canvas.restore();

    for (final (radius, alpha) in [(0.27, 0.92), (0.38, 0.5)]) {
      canvas.drawArc(
        Rect.fromCircle(center: sunCenter, radius: unit * radius),
        math.pi + 0.42,
        math.pi - 0.84,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.045
          ..strokeCap = StrokeCap.round
          ..color = FarlyColors.bone.withValues(alpha: alpha),
      );
    }

    final line = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = unit * 0.036;
    canvas.drawLine(
      at(0.17, horizonY),
      at(0.83, horizonY),
      line..color = FarlyColors.bone,
    );
    for (final (y, half, alpha) in [
      (0.67, 0.13, 0.75),
      (0.75, 0.08, 0.5),
      (0.82, 0.035, 0.3),
    ]) {
      canvas.drawLine(
        at(0.5 - half, y),
        at(0.5 + half, y),
        line..color = FarlyColors.horizon.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(FarlyMarkPainter oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.glyph != glyph ||
        oldDelegate.rounded != rounded ||
        oldDelegate.inset != inset;
  }
}
