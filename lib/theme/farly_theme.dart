import 'package:flutter/material.dart';

import 'farly_colors.dart';

ThemeData farlyTheme() {
  const text = TextTheme(
    headlineMedium: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      color: FarlyColors.bone,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: FarlyColors.bone,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      height: 1.4,
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
    dialogTheme: const DialogThemeData(backgroundColor: FarlyColors.field),
  );
}
