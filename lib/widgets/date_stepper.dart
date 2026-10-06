import 'package:flutter/material.dart';
import '../theme/theme_context.dart';

/// "‹  Today, Oct 6  ›" style navigator. Pass a null [onNext] to disable
/// forward navigation (e.g. when the next period would be in the future).
class DateStepper extends StatelessWidget {
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTapLabel;

  const DateStepper({
    super.key,
    required this.label,
    this.onPrevious,
    this.onNext,
    this.onTapLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Previous',
          onPressed: onPrevious,
        ),
        Expanded(
          child: Semantics(
            button: onTapLabel != null,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTapLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onTapLabel != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, size: 18, color: context.colors.textSecondary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: onNext == null ? 'No future dates' : 'Next',
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Date picker that only allows today and earlier. The result is clamped too,
/// so a future date can never come back from it.
Future<DateTime?> pickPastDate(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final first = DateTime(2020);
  var init = DateTime(initial.year, initial.month, initial.day);
  if (init.isAfter(today)) init = today;
  if (init.isBefore(first)) init = first;
  final picked = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: first,
    lastDate: today,
  );
  if (picked == null) return null;
  return picked.isAfter(today) ? today : picked;
}
