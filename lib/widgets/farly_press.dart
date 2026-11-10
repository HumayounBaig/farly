import 'package:flutter/material.dart';

import '../theme/farly_colors.dart';
import '../theme/farly_surfaces.dart';
import 'keys.dart';

class FarlyPress extends StatelessWidget {
  const FarlyPress({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final color = filled ? FarlyColors.night : FarlyColors.bone;
    final face = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: filled
          ? FarlySurfaces.sunPill()
          : FarlySurfaces.glass(radius: 20),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: filled ? color : FarlyColors.horizon),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return Pressable(
      onPressed: onPressed,
      child: expand ? SizedBox(width: double.infinity, child: face) : face,
    );
  }
}
