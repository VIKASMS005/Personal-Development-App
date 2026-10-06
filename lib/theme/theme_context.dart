import 'package:flutter/material.dart';
import 'app_colors_ext.dart';

/// Short accessors for the design system from any widget:
/// `context.colors.success`, `context.text.titleSmall`, `context.scheme.primary`.
extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppColorsExt get colors =>
      Theme.of(this).extension<AppColorsExt>() ?? (isDark ? AppColorsExt.dark : AppColorsExt.light);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
