import 'package:flutter/material.dart';

import 'farly_colors.dart';

abstract final class FarlySurfaces {
  static const sun = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [FarlyColors.sunrise, FarlyColors.horizon, FarlyColors.ember],
  );

  static const glassFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    // Slightly lifted top stop so pads/keys read as raised against the field.
    colors: [Color(0xF22E443C), Color(0xF2131C19)],
  );

  static const shadow = [
    BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 14)),
  ];

  static BoxDecoration glass({double radius = 24}) {
    return BoxDecoration(
      gradient: glassFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: FarlyColors.edge),
      boxShadow: shadow,
    );
  }

  static const glassDisc = BoxDecoration(
    shape: BoxShape.circle,
    gradient: glassFill,
    border: Border.fromBorderSide(BorderSide(color: FarlyColors.edge)),
    boxShadow: shadow,
  );

  static BoxDecoration sunDisc({double glow = 0.45}) {
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: sun,
      boxShadow: [
        BoxShadow(
          color: FarlyColors.horizon.withValues(alpha: glow),
          blurRadius: 32,
          spreadRadius: 1,
        ),
      ],
    );
  }

  static BoxDecoration sunPill({double radius = 20}) {
    return BoxDecoration(
      gradient: sun,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: FarlyColors.horizon.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
