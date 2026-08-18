import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class GradientBackground extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;
  final bool isDark;

  const GradientBackground({
    super.key,
    required this.child,
    this.gradient,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient ??
            (isDark ? AppColors.darkGradient : AppColors.authGradient),
      ),
      child: child,
    );
  }
}
