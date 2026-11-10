import 'package:flutter/material.dart';

import 'farly_colors.dart';

ThemeData farlyTheme() {
  const text = TextTheme(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.08,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
      color: FarlyColors.bone,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      color: FarlyColors.bone,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: FarlyColors.bone,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: FarlyColors.bone,
    ),
    bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: FarlyColors.mist),
    bodySmall: TextStyle(fontSize: 13, height: 1.35, color: FarlyColors.mist),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
      color: FarlyColors.mist,
    ),
    labelLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: FarlyColors.night,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FarlyColors.night,
    colorScheme: const ColorScheme.dark(
      surface: FarlyColors.night,
      primary: FarlyColors.horizon,
      onPrimary: FarlyColors.night,
      secondary: FarlyColors.mist,
      onSurface: FarlyColors.bone,
    ),
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dialogTheme: const DialogThemeData(backgroundColor: FarlyColors.field),
  );
}
