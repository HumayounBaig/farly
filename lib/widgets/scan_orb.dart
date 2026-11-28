import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import 'keys.dart';

class ScanOrb extends StatefulWidget {
  const ScanOrb({super.key, required this.scanning, required this.onPressed});

  final bool scanning;
  final VoidCallback? onPressed;

  @override
  State<ScanOrb> createState() => _ScanOrbState();
}

class _ScanOrbState extends State<ScanOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ScanOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Rings pulse only while scanning, and hold still when motion is reduced.
  void _sync() {
    final animate = widget.scanning && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
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
    return Pressable(
      label: label,
      dimWhenDisabled: false,
      onPressed: widget.scanning ? null : widget.onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 128,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _RingsPainter(
                        progress: _controller.value,
                        active: widget.scanning,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 92,
                  height: 92,
                  decoration: FarlySurfaces.sunDisc(),
                  child: const Icon(
                    Icons.wifi_tethering_rounded,
                    size: 38,
                    color: FarlyColors.night,
                  ),
                ),
              ],
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: FarlyColors.bone,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..style = PaintingStyle.stroke;
    if (!active) {
      canvas.drawCircle(
        center,
        58,
        paint
          ..strokeWidth = 1.5
          ..color = FarlyColors.horizon.withValues(alpha: 0.22),
      );
      return;
    }
    for (var wave = 0; wave < 3; wave++) {
      final phase = (progress + wave / 3) % 1;
      canvas.drawCircle(
        center,
        46 + phase * 18,
        paint
          ..strokeWidth = 2
          ..color = FarlyColors.horizon.withValues(alpha: (1 - phase) * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}
