import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/farly_colors.dart';

class FarlyPress extends StatelessWidget {
  const FarlyPress({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = Semantics(
      button: true,
      label: label,
      child: Material(
        color: filled ? FarlyColors.horizon : FarlyColors.raised,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: filled ? FarlyColors.night : FarlyColors.bone,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!expand) return child;
    return SizedBox(width: double.infinity, child: child);
  }
}
