import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'app_colors_ext.dart';
import 'app_palette.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Builds the light and dark [ThemeData] for the whole app.
///
/// Every Material component is themed here so screens can use stock widgets
/// (`FilledButton`, `Card`, `TextField`, `NavigationBar`, …) and get the
/// design system for free.
class AppTheme {
  AppTheme._();

  /// [fontFamily] is only for tests/golden images, where Google Fonts cannot
  /// be downloaded. The app itself always uses Plus Jakarta Sans.
  static ThemeData light({String? fontFamily}) => _build(
        brightness: Brightness.light,
        fontFamily: fontFamily,
        ext: AppColorsExt.light,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppPalette.lightPrimary,
          onPrimary: AppPalette.lightOnPrimary,
          primaryContainer: AppPalette.lightPrimaryContainer,
          onPrimaryContainer: AppPalette.lightOnPrimaryContainer,
          secondary: AppPalette.lightSecondary,
          onSecondary: AppPalette.lightOnSecondary,
          secondaryContainer: AppPalette.lightSecondaryContainer,
          onSecondaryContainer: AppPalette.lightOnSecondaryContainer,
          tertiary: AppPalette.lightWarning,
          onTertiary: AppPalette.lightOnPrimary,
          error: AppPalette.lightError,
          onError: AppPalette.lightOnPrimary,
          errorContainer: AppPalette.lightErrorContainer,
          onErrorContainer: AppPalette.lightError,
          surface: AppPalette.lightSurface,
          onSurface: AppPalette.lightTextPrimary,
          onSurfaceVariant: AppPalette.lightTextSecondary,
          surfaceContainerLowest: AppPalette.lightSurface,
          surfaceContainerLow: AppPalette.lightBackground,
          surfaceContainer: AppPalette.lightSurfaceMuted,
          surfaceContainerHigh: AppPalette.lightSurfaceMuted,
          surfaceContainerHighest: AppPalette.lightSurfaceStrong,
          outline: AppPalette.lightBorder,
          outlineVariant: AppPalette.lightDivider,
          shadow: AppPalette.scrim,
          scrim: AppPalette.scrim,
          inverseSurface: AppPalette.darkSurface,
          onInverseSurface: AppPalette.darkTextPrimary,
          inversePrimary: AppPalette.darkPrimary,
        ),
        background: AppPalette.lightBackground,
      );

  static ThemeData dark({String? fontFamily}) => _build(
        brightness: Brightness.dark,
        fontFamily: fontFamily,
        ext: AppColorsExt.dark,
        scheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppPalette.darkPrimary,
          onPrimary: AppPalette.darkOnPrimary,
          primaryContainer: AppPalette.darkPrimaryContainer,
          onPrimaryContainer: AppPalette.darkOnPrimaryContainer,
          secondary: AppPalette.darkSecondary,
          onSecondary: AppPalette.darkOnSecondary,
          secondaryContainer: AppPalette.darkSecondaryContainer,
          onSecondaryContainer: AppPalette.darkOnSecondaryContainer,
          tertiary: AppPalette.darkWarning,
          onTertiary: AppPalette.darkBackground,
          error: AppPalette.darkError,
          onError: AppPalette.darkBackground,
          errorContainer: AppPalette.darkErrorContainer,
          onErrorContainer: AppPalette.darkError,
          surface: AppPalette.darkSurface,
          onSurface: AppPalette.darkTextPrimary,
          onSurfaceVariant: AppPalette.darkTextSecondary,
          surfaceContainerLowest: AppPalette.darkBackground,
          surfaceContainerLow: AppPalette.darkBackground,
          surfaceContainer: AppPalette.darkSurfaceMuted,
          surfaceContainerHigh: AppPalette.darkSurfaceMuted,
          surfaceContainerHighest: AppPalette.darkSurfaceStrong,
          outline: AppPalette.darkBorder,
          outlineVariant: AppPalette.darkDivider,
          shadow: AppPalette.scrim,
          scrim: AppPalette.scrim,
          inverseSurface: AppPalette.lightSurface,
          onInverseSurface: AppPalette.lightTextPrimary,
          inversePrimary: AppPalette.lightPrimary,
        ),
        background: AppPalette.darkBackground,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppColorsExt ext,
    required Color background,
    String? fontFamily,
  }) {
    final isDark = brightness == Brightness.dark;
    final text = AppTypography.textTheme(
      primary: ext.textPrimary,
      secondary: ext.textSecondary,
      fontFamily: fontFamily,
    );

    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14);
    final buttonMinSize = WidgetStateProperty.all(const Size(64, AppSizes.minTouchTarget));

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [ext],
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: text,
      fontFamily: fontFamily,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerColor: ext.divider,
      disabledColor: ext.textDisabled,
      hintColor: ext.textDisabled,
      iconTheme: IconThemeData(color: ext.textSecondary, size: AppSizes.iconLg),
      primaryIconTheme: IconThemeData(color: scheme.primary, size: AppSizes.iconLg),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ext.textPrimary,
        iconTheme: IconThemeData(color: ext.textPrimary, size: AppSizes.iconLg),
        actionsIconTheme: IconThemeData(color: ext.textSecondary, size: AppSizes.iconLg),
        titleTextStyle: text.titleLarge,
        toolbarHeight: 60,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: ext.border),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonMinSize,
          padding: WidgetStateProperty.all(buttonPadding),
          shape: WidgetStateProperty.all(buttonShape),
          textStyle: WidgetStateProperty.all(text.labelLarge),
          elevation: WidgetStateProperty.all(0),
        ),
      ),
      // ElevatedButton is styled as the primary (filled) button so older
      // call sites look identical to FilledButton.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: ext.surfaceStrong,
          disabledForegroundColor: ext.textDisabled,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(64, AppSizes.minTouchTarget),
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ext.textPrimary,
          side: BorderSide(color: ext.border),
          minimumSize: const Size(64, AppSizes.minTouchTarget),
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ext.textSecondary,
          minimumSize: const Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        extendedTextStyle: text.labelLarge,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        border: inputBorder(ext.border),
        enabledBorder: inputBorder(ext.border),
        disabledBorder: inputBorder(ext.divider),
        focusedBorder: inputBorder(scheme.primary, 1.6),
        errorBorder: inputBorder(ext.error),
        focusedErrorBorder: inputBorder(ext.error, 1.6),
        labelStyle: text.bodyMedium?.copyWith(color: ext.textSecondary),
        floatingLabelStyle: text.labelMedium?.copyWith(color: scheme.primary),
        hintStyle: text.bodyMedium?.copyWith(color: ext.textDisabled),
        helperStyle: text.labelSmall,
        errorStyle: text.labelSmall?.copyWith(color: ext.error),
        prefixIconColor: ext.textSecondary,
        suffixIconColor: ext.textSecondary,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(scheme.surface),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: ext.border)),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        disabledColor: ext.surfaceMuted,
        side: BorderSide(color: ext.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        labelStyle: text.labelMedium?.copyWith(color: ext.textPrimary),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 6),
        showCheckmark: false,
        checkmarkColor: scheme.onPrimaryContainer,
        iconTheme: IconThemeData(color: ext.textSecondary, size: AppSizes.iconSm),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          minimumSize: WidgetStateProperty.all(const Size(0, 44)),
          textStyle: WidgetStateProperty.all(text.labelMedium),
          side: WidgetStateProperty.all(BorderSide(color: ext.border)),
          shape: WidgetStateProperty.all(
            const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.primaryContainer : scheme.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : ext.textSecondary,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : ext.textSecondary,
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? ext.textPrimary : ext.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: AppSizes.iconLg,
            color: s.contains(WidgetState.selected) ? scheme.onPrimaryContainer : ext.textSecondary,
          ),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: ext.textSecondary,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: ext.divider,
        overlayColor: WidgetStateProperty.all(scheme.primary.withValues(alpha: 0.06)),
        tabAlignment: TabAlignment.fill,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : ext.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : ext.surfaceStrong,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : ext.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs))),
        side: BorderSide(color: ext.textSecondary, width: 1.6),
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return ext.surfaceStrong;
          return s.contains(WidgetState.selected) ? scheme.primary : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : ext.textSecondary,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: ext.chartTrack,
        circularTrackColor: ext.chartTrack,
        linearMinHeight: 6,
        refreshBackgroundColor: scheme.surface,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: ext.chartTrack,
        thumbColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(color: ext.divider, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        iconColor: ext.textSecondary,
        textColor: ext.textPrimary,
        titleTextStyle: text.titleSmall,
        subtitleTextStyle: text.bodySmall,
        minVerticalPadding: AppSpacing.sm,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: ext.textSecondary,
        collapsedIconColor: ext.textSecondary,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: ext.textSecondary),
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: AppPalette.scrim.withValues(alpha: isDark ? 0.5 : 0.12),
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: ext.border)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: AppRadius.smAll),
        textStyle: text.labelSmall?.copyWith(color: scheme.onInverseSurface),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
        textStyle: text.labelSmall,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
        headerBackgroundColor: scheme.surface,
        headerForegroundColor: ext.textPrimary,
        dividerColor: ext.divider,
        todayBorder: BorderSide(color: scheme.primary),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
        hourMinuteShape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        dayPeriodShape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        dayPeriodBorderSide: BorderSide(color: ext.border),
        dialBackgroundColor: ext.surfaceMuted,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
