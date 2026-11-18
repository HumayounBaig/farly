import 'package:flutter/material.dart';

/// Night field, warm horizon. The palette stays off Apple's black glass remote.
///
/// Keep the teal-night + amber-horizon identity. Prefer polishing [mist] /
/// [edge] for secondary chrome contrast before touching brand anchors.
abstract final class FarlyColors {
  static const night = Color(0xFF0B110F);
  static const deep = Color(0xFF14292A);
  static const field = Color(0xFF17221F);
  static const raised = Color(0xFF22322D);
  static const horizon = Color(0xFFF0B26A);
  static const sunrise = Color(0xFFFFDCA8);
  /// Warm accent inside the sun gradient — kept distinct from [clay].
  static const ember = Color(0xFFE8923A);
  /// Secondary labels, drag handles, quiet icons — a touch brighter than the
  /// field so arrange-mode chrome stays readable without competing with bone.
  static const mist = Color(0xFFB6CEC9);
  static const bone = Color(0xFFF6F1E8);
  /// Destructive / hide — cooler coral so it doesn't read as the sun CTA.
  static const clay = Color(0xFFD96B5C);
  static const leaf = Color(0xFF8FD9AE);
  /// Glass outlines. Slightly stronger than a hairline so keys separate from
  /// the night field, especially in arrange mode.
  static const edge = Color(0x22FFFFFF);
  /// Soft wash behind arrange-mode chrome (tint of horizon on night).
  static const arrangeWash = Color(0x18F0B26A);
}
