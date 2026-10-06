import 'package:flutter/material.dart';

/// Raw color values for both themes.
///
/// Only the theme layer (`lib/theme/`) reads this file. Widgets read colors
/// from `Theme.of(context).colorScheme` or `context.colors` so they adapt to
/// light and dark mode automatically.
class AppPalette {
  AppPalette._();

  // ── Light ────────────────────────────────────────────────────────────────
  static const lightPrimary = Color(0xFF0E7C66);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFD7F0E8);
  static const lightOnPrimaryContainer = Color(0xFF053B30);
  static const lightSecondary = Color(0xFF4A56C8);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFE4E7FA);
  static const lightOnSecondaryContainer = Color(0xFF1C2466);

  static const lightBackground = Color(0xFFF6F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceMuted = Color(0xFFF1F3F5);
  static const lightSurfaceStrong = Color(0xFFE7EAEE);
  static const lightTextPrimary = Color(0xFF111827);
  static const lightTextSecondary = Color(0xFF515B6B);
  static const lightTextDisabled = Color(0xFF9AA2AF);
  static const lightBorder = Color(0xFFE1E5EA);
  static const lightDivider = Color(0xFFECEFF2);

  static const lightSuccess = Color(0xFF12703A);
  static const lightSuccessContainer = Color(0xFFE5F5EA);
  static const lightWarning = Color(0xFFB45309);
  static const lightWarningContainer = Color(0xFFFDF1E1);
  static const lightError = Color(0xFFC62828);
  static const lightErrorContainer = Color(0xFFFCEBEB);
  static const lightInfo = Color(0xFF1D4ED8);
  static const lightInfoContainer = Color(0xFFE7EEFD);

  static const lightChartMuted = Color(0xFFB8C1CC);
  static const lightChartTrack = Color(0xFFEDF0F3);

  // ── Dark ─────────────────────────────────────────────────────────────────
  static const darkPrimary = Color(0xFF5CC9AC);
  static const darkOnPrimary = Color(0xFF00382D);
  static const darkPrimaryContainer = Color(0xFF143A31);
  static const darkOnPrimaryContainer = Color(0xFFB9EBDB);
  static const darkSecondary = Color(0xFFA3AAF5);
  static const darkOnSecondary = Color(0xFF1A2160);
  static const darkSecondaryContainer = Color(0xFF262C55);
  static const darkOnSecondaryContainer = Color(0xFFDDE0FF);

  static const darkBackground = Color(0xFF0F1216);
  static const darkSurface = Color(0xFF171B21);
  static const darkSurfaceMuted = Color(0xFF1E232B);
  static const darkSurfaceStrong = Color(0xFF272D37);
  static const darkTextPrimary = Color(0xFFE7E9EC);
  static const darkTextSecondary = Color(0xFFA2A9B5);
  static const darkTextDisabled = Color(0xFF5F6774);
  static const darkBorder = Color(0xFF2A3039);
  static const darkDivider = Color(0xFF232830);

  static const darkSuccess = Color(0xFF6FCB91);
  static const darkSuccessContainer = Color(0xFF17291F);
  static const darkWarning = Color(0xFFE6B062);
  static const darkWarningContainer = Color(0xFF2F2516);
  static const darkError = Color(0xFFF08C84);
  static const darkErrorContainer = Color(0xFF34191A);
  static const darkInfo = Color(0xFF8DB3F7);
  static const darkInfoContainer = Color(0xFF172338);

  static const darkChartMuted = Color(0xFF465060);
  static const darkChartTrack = Color(0xFF222831);

  static const scrim = Color(0xFF000000);
}
