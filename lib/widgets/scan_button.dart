import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/farly_colors.dart';

class ScanButton extends StatefulWidget {
  const ScanButton({super.key, required this.scanning, required this.onPressed});

  final bool scanning;
  final VoidCallback? onPressed;

  @override
  State<ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<ScanButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didUpdateWidget(ScanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.scanning && _controller.isAnimating) {
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
    final label = widget.scanning ? 'Listening' : 'Scan the room';
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: Material(
          color: FarlyColors.horizon,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.scanning
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    widget.onPressed?.call();
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SweepPainter(progress: _controller.value),
                    );
                  },
                ),
                Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: FarlyColors.night,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  const _SweepPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final x = size.width * progress;
    canvas.drawRect(
      Rect.fromLTWH(x - 40, 0, 80, size.height),
      Paint()..color = const Color(0x33FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_SweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
