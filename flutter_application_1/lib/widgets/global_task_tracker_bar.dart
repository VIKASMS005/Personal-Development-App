import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/task_tracker_provider.dart';
import '../utils/app_colors.dart';

/// Floating mini-tracker bar that stays visible across all app screens
/// while a task timer is actively running.
class GlobalTaskTrackerBar extends StatelessWidget {
  const GlobalTaskTrackerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TaskTrackerProvider>();

    if (!tracker.isTracking || tracker.activeTodo == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final todo = tracker.activeTodo!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.tasks.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.tasks.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Glowing Task Indicator
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.tasks.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_rounded,
                color: AppColors.tasks,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),

            // Task Name and Category
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.tasks.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          todo.category,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.tasks,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tracker.isPaused ? 'Paused' : 'Tracking in background',
                        style: TextStyle(
                          fontSize: 10,
                          color: tracker.isPaused
                              ? Colors.amber
                              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Live Timer Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tracker.formattedTime,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.tasks,
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Pause / Resume Button
            IconButton(
              icon: Icon(
                tracker.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: AppColors.tasks,
                size: 22,
              ),
              onPressed: () => tracker.togglePauseResume(),
              tooltip: tracker.isPaused ? 'Resume' : 'Pause',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

            // Finish & Save Button
            IconButton(
              icon: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 22,
              ),
              onPressed: () async {
                await tracker.finish(context);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎉 Focus session recorded successfully!'),
                      backgroundColor: AppColors.success,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              tooltip: 'Finish & Save',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

            // Cancel Button
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                size: 18,
              ),
              onPressed: () => tracker.cancel(),
              tooltip: 'Discard Timer',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 0.2, end: 0, duration: 250.ms).fadeIn();
  }
}
