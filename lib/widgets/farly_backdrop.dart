import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/farly_colors.dart';

class FarlyBackdrop extends StatelessWidget {
  const FarlyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: FarlyColors.night,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [FarlyColors.deep, FarlyColors.night],
            stops: [0, 0.62],
          ),
        ),
        child: CustomPaint(painter: const _GlowPainter(), child: child),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width / 2, size.height * 0.1);
    final glowRadius = size.width * 0.95;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            FarlyColors.horizon.withValues(alpha: 0.16),
            FarlyColors.horizon.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    final rise = Offset(size.width / 2, size.height * 1.08);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var band = 1; band <= 4; band++) {
      canvas.drawCircle(
        rise,
        size.width * (0.42 + band * 0.24),
        ring..color = FarlyColors.bone.withValues(alpha: 0.05 - band * 0.008),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => false;
}
