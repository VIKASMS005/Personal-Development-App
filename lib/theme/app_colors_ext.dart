import 'package:flutter/material.dart';
import 'app_palette.dart';

/// Tone of a status / badge / banner. Each tone has a foreground and a soft
/// container color in both themes.
enum StatusTone { neutral, primary, success, warning, error, info }

/// Semantic colors that Material's [ColorScheme] has no slot for.
///
/// Read with `context.colors` (see `theme_context.dart`).
@immutable
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color border;
  final Color divider;
  final Color surfaceMuted;
  final Color surfaceStrong;

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color error;
  final Color errorContainer;
  final Color info;
  final Color infoContainer;

  /// Main data series (current period, today, highlighted bar).
  final Color chartPrimary;

  /// Comparison series (previous period, secondary metric).
  final Color chartSecondary;

  /// Ordinary bars that are not highlighted.
  final Color chartMuted;

  /// Empty track behind bars and progress rings.
  final Color chartTrack;

  const AppColorsExt({
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.border,
    required this.divider,
    required this.surfaceMuted,
    required this.surfaceStrong,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.error,
    required this.errorContainer,
    required this.info,
    required this.infoContainer,
    required this.chartPrimary,
    required this.chartSecondary,
    required this.chartMuted,
    required this.chartTrack,
  });

  static const light = AppColorsExt(
    textPrimary: AppPalette.lightTextPrimary,
    textSecondary: AppPalette.lightTextSecondary,
    textDisabled: AppPalette.lightTextDisabled,
    border: AppPalette.lightBorder,
    divider: AppPalette.lightDivider,
    surfaceMuted: AppPalette.lightSurfaceMuted,
    surfaceStrong: AppPalette.lightSurfaceStrong,
    success: AppPalette.lightSuccess,
    successContainer: AppPalette.lightSuccessContainer,
    warning: AppPalette.lightWarning,
    warningContainer: AppPalette.lightWarningContainer,
    error: AppPalette.lightError,
    errorContainer: AppPalette.lightErrorContainer,
    info: AppPalette.lightInfo,
    infoContainer: AppPalette.lightInfoContainer,
    chartPrimary: AppPalette.lightPrimary,
    chartSecondary: AppPalette.lightSecondary,
    chartMuted: AppPalette.lightChartMuted,
    chartTrack: AppPalette.lightChartTrack,
  );

  static const dark = AppColorsExt(
    textPrimary: AppPalette.darkTextPrimary,
    textSecondary: AppPalette.darkTextSecondary,
    textDisabled: AppPalette.darkTextDisabled,
    border: AppPalette.darkBorder,
    divider: AppPalette.darkDivider,
    surfaceMuted: AppPalette.darkSurfaceMuted,
    surfaceStrong: AppPalette.darkSurfaceStrong,
    success: AppPalette.darkSuccess,
    successContainer: AppPalette.darkSuccessContainer,
    warning: AppPalette.darkWarning,
    warningContainer: AppPalette.darkWarningContainer,
    error: AppPalette.darkError,
    errorContainer: AppPalette.darkErrorContainer,
    info: AppPalette.darkInfo,
    infoContainer: AppPalette.darkInfoContainer,
    chartPrimary: AppPalette.darkPrimary,
    chartSecondary: AppPalette.darkSecondary,
    chartMuted: AppPalette.darkChartMuted,
    chartTrack: AppPalette.darkChartTrack,
  );

  /// Foreground color for a [StatusTone].
  Color toneColor(StatusTone tone, ColorScheme scheme) {
    switch (tone) {
      case StatusTone.neutral:
        return textSecondary;
      case StatusTone.primary:
        return scheme.primary;
      case StatusTone.success:
        return success;
      case StatusTone.warning:
        return warning;
      case StatusTone.error:
        return error;
      case StatusTone.info:
        return info;
    }
  }

  /// Soft background color for a [StatusTone].
  Color toneContainer(StatusTone tone, ColorScheme scheme) {
    switch (tone) {
      case StatusTone.neutral:
        return surfaceMuted;
      case StatusTone.primary:
        return scheme.primaryContainer;
      case StatusTone.success:
        return successContainer;
      case StatusTone.warning:
        return warningContainer;
      case StatusTone.error:
        return errorContainer;
      case StatusTone.info:
        return infoContainer;
    }
  }

  @override
  AppColorsExt copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? border,
    Color? divider,
    Color? surfaceMuted,
    Color? surfaceStrong,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? error,
    Color? errorContainer,
    Color? info,
    Color? infoContainer,
    Color? chartPrimary,
    Color? chartSecondary,
    Color? chartMuted,
    Color? chartTrack,
  }) {
    return AppColorsExt(
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      chartPrimary: chartPrimary ?? this.chartPrimary,
      chartSecondary: chartSecondary ?? this.chartSecondary,
      chartMuted: chartMuted ?? this.chartMuted,
      chartTrack: chartTrack ?? this.chartTrack,
    );
  }

  @override
  AppColorsExt lerp(ThemeExtension<AppColorsExt>? other, double t) {
    if (other is! AppColorsExt) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExt(
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textDisabled: l(textDisabled, other.textDisabled),
      border: l(border, other.border),
      divider: l(divider, other.divider),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceStrong: l(surfaceStrong, other.surfaceStrong),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      error: l(error, other.error),
      errorContainer: l(errorContainer, other.errorContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
      chartPrimary: l(chartPrimary, other.chartPrimary),
      chartSecondary: l(chartSecondary, other.chartSecondary),
      chartMuted: l(chartMuted, other.chartMuted),
      chartTrack: l(chartTrack, other.chartTrack),
    );
  }
}
