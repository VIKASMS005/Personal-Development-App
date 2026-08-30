import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class AnimatedListItem extends StatelessWidget {
  final Widget child;
  final int index;

  const AnimatedListItem({
    super.key,
    required this.child,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return child
        .animate()
        .fadeIn(duration: 350.ms, delay: (index * 60).ms)
        .slideX(begin: 0.08, end: 0, duration: 350.ms, delay: (index * 60).ms);
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? accentColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (accentColor == null) return card;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(color: accentColor!, width: 4),
        ),
      ),
      child: card,
    );
  }
}
