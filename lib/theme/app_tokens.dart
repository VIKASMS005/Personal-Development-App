import 'package:flutter/material.dart';

/// Spacing scale. Every padding, gap and margin in the app comes from here.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Horizontal padding of every screen.
  static const double screen = 16;

  /// Vertical gap between two sections of a screen.
  static const double section = 28;

  /// Space left under scrolling content so a FAB never covers the last item.
  static const double fabClearance = 96;

  /// Widest a content column grows on tablets / landscape.
  static const double maxContentWidth = 720;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: screen);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}

/// Corner radius scale.
class AppRadius {
  AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Motion. Short and calm; nothing in the app animates for longer than [slow].
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}

/// Sizes that need to be consistent across components.
class AppSizes {
  AppSizes._();

  static const double minTouchTarget = 48;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconBadge = 40;
  static const double buttonHeight = 52;
}
