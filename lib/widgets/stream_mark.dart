import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';

/// Letter / glyph mark for a streaming app button (Netflix N, YouTube ▶, …).
class StreamMark extends StatelessWidget {
  const StreamMark({
    super.key,
    required this.mark,
    this.tint = FarlyColors.horizon,
    this.size = 36,
  });

  final String mark;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final short = mark.length <= 2;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: tint.withValues(alpha: 0.55)),
      ),
      child: Text(
        mark,
        style: TextStyle(
          color: FarlyColors.bone,
          fontSize: short ? size * 0.42 : size * 0.28,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
