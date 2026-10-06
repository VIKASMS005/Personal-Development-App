import 'package:flutter/material.dart';
import '../widgets/ds/ds.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.slow,
          curve: AppMotion.curve,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: AppRadius.lgAll,
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Image.asset(
                    'assets/images/app_logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: scheme.primaryContainer,
                      child: Icon(Icons.eco_rounded, size: 48, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Grow', style: context.text.headlineMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text('Build better days', style: context.text.bodyMedium?.copyWith(color: context.colors.textSecondary)),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
