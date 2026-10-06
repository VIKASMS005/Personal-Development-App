import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The type scale.
///
/// | Role                     | TextTheme slot   | Size / weight |
/// |--------------------------|------------------|---------------|
/// | Hero number (steps)      | displaySmall     | 40 / 700      |
/// | Statistic value          | headlineMedium   | 26 / 700      |
/// | Page title               | headlineSmall    | 24 / 700      |
/// | Dialog / sheet title     | titleLarge       | 20 / 700      |
/// | Section title            | titleMedium      | 17 / 650      |
/// | Card / list item title   | titleSmall       | 15 / 600      |
/// | Body                     | bodyLarge/Medium | 16, 14 / 400  |
/// | Secondary text           | bodySmall        | 13 / 400      |
/// | Button text              | labelLarge       | 15 / 600      |
/// | Label / chip             | labelMedium      | 13 / 600      |
/// | Caption / overline       | labelSmall       | 12 / 500      |
///
/// Widgets pick a slot from this table instead of setting `fontSize`.
class AppTypography {
  AppTypography._();

  static const _tabular = [FontFeature.tabularFigures()];

  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
    String? fontFamily,
  }) {
    final base = TextTheme(
      displaySmall: TextStyle(
        fontSize: 40,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: primary,
        fontFeatures: _tabular,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
        fontFeatures: _tabular,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: secondary,
      ),
    );

    if (fontFamily != null) {
      return base.apply(fontFamily: fontFamily);
    }
    return GoogleFonts.plusJakartaSansTextTheme(base);
  }
}
