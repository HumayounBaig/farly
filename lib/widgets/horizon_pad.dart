import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/remote_action.dart';
import '../theme/farly_colors.dart';

class HorizonPad extends StatefulWidget {
  const HorizonPad({super.key, required this.onAction});

  final ValueChanged<RemoteAction> onAction;

  @override
  State<HorizonPad> createState() => _HorizonPadState();
}

class _HorizonPadState extends State<HorizonPad> {
  Offset? _finger;
  Offset _pending = Offset.zero;

  void _emit(RemoteAction action) {
    HapticFeedback.lightImpact();
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Direction pad',
      hint: 'Swipe to move. Tap to select.',
      child: GestureDetector(
        onTap: () => _emit(RemoteAction.select),
        onPanStart: (details) {
          setState(() {
            _finger = details.localPosition;
            _pending = Offset.zero;
          });
        },
        onPanUpdate: (details) {
          final next = _pending + details.delta;
          if (next.dx.abs() > 42 && next.dx.abs() > next.dy.abs()) {
            _emit(next.dx > 0 ? RemoteAction.right : RemoteAction.left);
            _pending = Offset.zero;
          } else if (next.dy.abs() > 42) {
            _emit(next.dy > 0 ? RemoteAction.down : RemoteAction.up);
            _pending = Offset.zero;
          } else {
            _pending = next;
          }
          setState(() => _finger = details.localPosition);
        },
        onPanEnd: (_) => setState(() => _finger = null),
        onPanCancel: () => setState(() => _finger = null),
        child: CustomPaint(
          painter: _HorizonPainter(finger: _finger),
          child: const SizedBox(height: 280, width: double.infinity),
        ),
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  const _HorizonPainter({required this.finger});

  final Offset? finger;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final field = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawRRect(field, Paint()..color = FarlyColors.raised);

    final line = Paint()
      ..color = FarlyColors.line
      ..strokeWidth = 1;
    for (var band = 1; band <= 4; band++) {
      final y = size.height * band / 5;
      canvas.drawLine(Offset(28, y), Offset(size.width - 28, y), line);
    }

    final glow = finger ?? Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      glow,
      22,
      Paint()..color = FarlyColors.horizon.withValues(alpha: 0.18),
    );
    canvas.drawCircle(glow, 7, Paint()..color = FarlyColors.horizon);
  }

  @override
  bool shouldRepaint(_HorizonPainter oldDelegate) => oldDelegate.finger != finger;
}
