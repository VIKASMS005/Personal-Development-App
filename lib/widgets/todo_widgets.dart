import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/todo.dart';
import 'ds/ds.dart';

String formatTrackedTime(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String formatDue(DateTime due) {
  final now = DateTime.now();
  final hasTime = due.hour != 0 || due.minute != 0;
  final time = hasTime ? DateFormat('h:mm a').format(due) : null;
  String day;
  if (DateUtils.isSameDay(due, now)) {
    day = 'Today';
  } else if (DateUtils.isSameDay(due, now.add(const Duration(days: 1)))) {
    day = 'Tomorrow';
  } else if (DateUtils.isSameDay(due, now.subtract(const Duration(days: 1)))) {
    day = 'Yesterday';
  } else if (due.year == now.year) {
    day = DateFormat('EEE, d MMM').format(due);
  } else {
    day = DateFormat('d MMM yyyy').format(due);
  }
  return time == null ? day : '$day, $time';
}

/// Status of a task/goal as a badge: Completed, Missed/Overdue, or the time
/// left in the 2-hour grace window. Null when the item is simply scheduled.
Widget? todoStatusBadge(Todo t) {
  if (t.completed) {
    return const StatusBadge(label: 'Completed', tone: StatusTone.success, icon: Icons.check_rounded);
  }
  if (t.isMissed) {
    return StatusBadge(
      label: t.isGoal ? 'Overdue' : 'Missed',
      tone: StatusTone.error,
      icon: Icons.error_outline_rounded,
    );
  }
  if (t.isInGracePeriod) {
    final remaining = t.absoluteDeadline!.difference(DateTime.now());
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return StatusBadge(
      label: h > 0 ? '${h}h ${m}m left' : '${m}m left',
      tone: StatusTone.warning,
      icon: Icons.hourglass_bottom_rounded,
    );
  }
  return null;
}

/// Row of actions shared by task and goal cards.
class TodoActions extends StatelessWidget {
  final bool isTracking;
  final VoidCallback onTrack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TodoActions({
    super.key,
    required this.isTracking,
    required this.onTrack,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: isTracking ? 'Stop focus timer' : 'Start focus timer',
          onPressed: onTrack,
          icon: Icon(
            isTracking ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded,
            color: isTracking ? context.colors.error : context.scheme.primary,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded, color: context.colors.error),
                title: Text('Delete', style: TextStyle(color: context.colors.error)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A task in a list: checkbox, title, when it's due, priority and status.
class TaskCard extends StatelessWidget {
  final Todo todo;
  final VoidCallback? onToggle;
  final Widget? actions;

  const TaskCard({super.key, required this.todo, required this.onToggle, this.actions});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = todo;
    final status = todoStatusBadge(t);
    return AppCard(
      borderColor: t.isMissed ? colors.error.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxs, AppSpacing.xs, AppSpacing.xxs, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: t.completed ? 'Mark as not done' : 'Mark as done',
            child: Checkbox(
              value: t.completed,
              onChanged: onToggle == null ? null : (_) => onToggle!(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.medium,
                    style: context.text.titleSmall!.copyWith(
                      decoration: t.completed ? TextDecoration.lineThrough : null,
                      color: t.completed ? colors.textSecondary : colors.textPrimary,
                    ),
                    child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  if (t.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  _MetaLine(todo: t),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xxs + 2,
                    runSpacing: AppSpacing.xxs + 2,
                    children: [
                      PriorityBadge(priority: t.priority),
                      if (status != null) status,
                      if (t.timeSpentSeconds > 0)
                        StatusBadge(
                          label: formatTrackedTime(t.timeSpentSeconds),
                          icon: Icons.timer_outlined,
                          outlined: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (actions != null) actions!,
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final Todo todo;
  const _MetaLine({required this.todo});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.text.labelSmall;
    final dueColor = todo.isMissed ? colors.error : colors.textSecondary;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (todo.dueDate != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: dueColor),
              const SizedBox(width: 4),
              Flexible(child: Text(formatDue(todo.dueDate!), style: style?.copyWith(color: dueColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(categoryIcon(todo.category), size: 14, color: colors.textSecondary),
            const SizedBox(width: 4),
            Flexible(child: Text(todo.category, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        if (todo.reminderDateTime != null)
          Icon(Icons.notifications_none_rounded, size: 14, color: colors.textSecondary, semanticLabel: 'Has reminder'),
      ],
    );
  }
}

/// A goal: longer horizon, so it shows a deadline timeline instead of a
/// simple due time. Visually related to [TaskCard] but distinct.
class GoalProgressCard extends StatelessWidget {
  final Todo goal;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final Widget? actions;

  const GoalProgressCard({super.key, required this.goal, this.onTap, this.onToggle, this.actions});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final g = goal;
    final status = todoStatusBadge(g);
    final now = DateTime.now();

    double elapsed = 0;
    String? timeLeft;
    if (g.dueDate != null) {
      final start = g.createdAt ?? g.updatedAt;
      final total = g.dueDate!.difference(start).inMinutes;
      final done = now.difference(start).inMinutes;
      elapsed = total <= 0 ? 1 : (done / total).clamp(0.0, 1.0);
      final days = DateTime(g.dueDate!.year, g.dueDate!.month, g.dueDate!.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      if (g.completed) {
        timeLeft = 'Done';
      } else if (days > 1) {
        timeLeft = '$days days left';
      } else if (days == 1) {
        timeLeft = '1 day left';
      } else if (days == 0) {
        timeLeft = 'Due today';
      } else {
        timeLeft = '${-days} ${-days == 1 ? 'day' : 'days'} overdue';
      }
    }

    final meterColor = g.completed
        ? colors.success
        : g.isMissed
            ? colors.error
            : elapsed > 0.85
                ? colors.warning
                : colors.chartPrimary;

    return AppCard(
      onTap: onTap,
      borderColor: g.isMissed ? colors.error.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xxs, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onToggle != null || g.completed)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: g.completed,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onChanged: onToggle == null ? null : (_) => onToggle!(),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(Icons.flag_outlined, size: AppSizes.iconLg, color: context.scheme.primary),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(
                        decoration: g.completed ? TextDecoration.lineThrough : null,
                        color: g.completed ? colors.textSecondary : colors.textPrimary,
                      ),
                    ),
                    if (g.dueDate != null) ...[
                      const SizedBox(height: 2),
                      Text('Deadline ${formatDue(g.dueDate!)}', style: context.text.labelSmall),
                    ],
                  ],
                ),
              ),
              if (actions != null) actions! else const SizedBox(width: AppSpacing.sm),
            ],
          ),
          if (g.dueDate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Timeline', style: context.text.labelSmall)),
                      Text(
                        timeLeft ?? '',
                        style: context.text.labelSmall?.copyWith(
                          color: g.isMissed ? colors.error : colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs + 2),
                  LinearMeter(value: g.completed ? 1 : elapsed, color: meterColor),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xxs + 2,
            runSpacing: AppSpacing.xxs + 2,
            children: [
              PriorityBadge(priority: g.priority),
              if (status != null) status,
              StatusBadge(label: g.category, icon: categoryIcon(g.category), outlined: true),
              if (g.timeSpentSeconds > 0)
                StatusBadge(label: formatTrackedTime(g.timeSpentSeconds), icon: Icons.timer_outlined, outlined: true),
            ],
          ),
        ],
      ),
    );
  }
}
