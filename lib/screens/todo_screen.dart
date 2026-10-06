import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/todo.dart';
import '../utils/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/global_task_tracker_bar.dart';
import 'forms/todo_form.dart';
import 'task_report_screen.dart';

class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen>
    with SingleTickerProviderStateMixin {
  int _selectedMainTab = 0; // 0=Tasks, 1=Goals
  int _selectedStatusFilter = 0; // 0=Scheduled/Active, 1=Completed, 2=Missed/Overdue, 3=All
  String _searchQuery = '';

  static const _priorityLabels = {
    1: ('Urgent', AppColors.error),
    2: ('Important', AppColors.warning),
    3: ('Medium Priority', AppColors.secondary),
    4: ('Low Priority', AppColors.lightTextSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final todoProvider = context.watch<TodoProvider>();

    final isGoalsTab = _selectedMainTab == 1;

    // Filter by permanent type
    final currentDomainList = isGoalsTab ? todoProvider.goals : todoProvider.tasks;

    final scheduledOrActive = isGoalsTab ? todoProvider.activeGoals : todoProvider.scheduledTasks;
    final completed = isGoalsTab ? todoProvider.completedGoals : todoProvider.completedTasks;
    final missedOrOverdue = isGoalsTab ? todoProvider.missedGoals : todoProvider.missedTasks;
    final all = currentDomainList;

    final statusFilters = isGoalsTab
        ? [
            'Active\n(${scheduledOrActive.length})',
            'Completed\n(${completed.length})',
            'Overdue\n(${missedOrOverdue.length})',
            'All\n(${all.length})',
          ]
        : [
            'Scheduled\n(${scheduledOrActive.length})',
            'Completed\n(${completed.length})',
            'Missed\n(${missedOrOverdue.length})',
            'All\n(${all.length})',
          ];

    List<Todo> sourceList;
    switch (_selectedStatusFilter) {
      case 0:
        sourceList = scheduledOrActive;
        break;
      case 1:
        sourceList = completed;
        break;
      case 2:
        sourceList = missedOrOverdue;
        break;
      case 3:
      default:
        sourceList = all;
        break;
    }

    List<Todo> filtered = sourceList.where((t) {
      if (_searchQuery.isNotEmpty) {
        if (!t.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
            !t.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & Goals'),
        actions: [
          IconButton(
            tooltip: 'Reports & Analytics',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.tasks.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.insights_rounded,
                  color: AppColors.tasks, size: 20),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TaskReportScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isGoalsTab ? AppColors.secondary : AppColors.tasks,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () async {
          final t = await TodoForm.show(context);
          if (t != null && auth.uid != null) {
            t.uid = auth.uid!;
            await todoProvider.addTodo(t);
          }
        },
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: Column(
        children: [
          const GlobalTaskTrackerBar(),

          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── 1. Top Segmented Switcher: [ Tasks ] [ Goals ] ────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            // Tasks Tab
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() {
                                  _selectedMainTab = 0;
                                  _selectedStatusFilter = 0;
                                }),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _selectedMainTab == 0
                                        ? AppColors.tasks
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _selectedMainTab == 0
                                        ? [
                                            BoxShadow(
                                              color: AppColors.tasks.withValues(alpha: 0.3),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.task_alt_rounded,
                                        size: 18,
                                        color: _selectedMainTab == 0
                                            ? Colors.white
                                            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'Tasks (${todoProvider.tasks.length})',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: _selectedMainTab == 0
                                                  ? Colors.white
                                                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Goals Tab
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(() {
                                  _selectedMainTab = 1;
                                  _selectedStatusFilter = 0;
                                }),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _selectedMainTab == 1
                                        ? AppColors.secondary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _selectedMainTab == 1
                                        ? [
                                            BoxShadow(
                                              color: AppColors.secondary.withValues(alpha: 0.3),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.flag_rounded,
                                        size: 18,
                                        color: _selectedMainTab == 1
                                            ? Colors.white
                                            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'Goals (${todoProvider.goals.length})',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: _selectedMainTab == 1
                                                  ? Colors.white
                                                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── 2. Search Bar ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: isGoalsTab ? 'Search goals...' : 'Search tasks...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),

                    // ── 3. Status Filters: Scheduled/Active -> Completed -> Missed -> All ──
                    // All four fit on screen so "All" is never hidden off the edge.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: List.generate(statusFilters.length, (i) {
                          final isSelected = _selectedStatusFilter == i;
                          final isMissedTab = i == 2;
                          final activeColor = isGoalsTab ? AppColors.secondary : AppColors.tasks;

                          final color = isMissedTab ? AppColors.error : activeColor;

                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: i == statusFilters.length - 1 ? 0 : 6),
                              child: Material(
                                color: isSelected ? color.withValues(alpha: 0.18) : Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: isSelected ? color.withValues(alpha: 0.5) : theme.dividerColor,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => setState(() => _selectedStatusFilter = i),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        statusFilters[i],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.25,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? color : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── 4. Items List View ────────────────────────────────────
                    Expanded(
                      child: filtered.isEmpty
                          ? EmptyState(
                              icon: isGoalsTab ? Icons.flag_rounded : Icons.task_alt_rounded,
                              title: _selectedStatusFilter == 0
                                  ? (isGoalsTab ? 'No Active Goals' : 'No Scheduled Tasks')
                                  : _selectedStatusFilter == 1
                                      ? (isGoalsTab ? 'No Completed Goals Yet' : 'No Completed Tasks Yet')
                                      : _selectedStatusFilter == 2
                                          ? (isGoalsTab ? 'No Overdue Goals!' : 'No Missed Deadlines!')
                                          : (isGoalsTab ? 'No Goals Found' : 'No Tasks Found'),
                              subtitle: _selectedStatusFilter == 2
                                  ? (isGoalsTab ? 'All your goals are on track!' : 'Great job keeping up with all your deadlines!')
                                  : (isGoalsTab ? 'Tap Add Goal to set a long-term milestone (> 7 days).' : 'Tap Add Task to create an actionable task (<= 7 days).'),
                              action: _selectedStatusFilter != 2
                                  ? FilledButton(
                                      onPressed: () async {
                                        final t = await TodoForm.show(context);
                                        if (t != null && auth.uid != null) {
                                          t.uid = auth.uid!;
                                          await todoProvider.addTodo(t);
                                        }
                                      },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: isGoalsTab ? AppColors.secondary : AppColors.tasks,
                                        foregroundColor: Colors.white,
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(16),
                                      ),
                                      child: const Icon(Icons.add_rounded, size: 28),
                                    )
                                  : null,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final t = filtered[i];
                                final priority = _priorityLabels[t.priority] ??
                                    ('Low Priority', AppColors.lightTextSecondary);
                                final isMissed = t.isMissed;
                                final inGrace = t.isInGracePeriod;

                                return Dismissible(
                                  key: Key(t.id),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (direction) async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(t.isGoal ? 'Delete Goal?' : 'Delete Task?'),
                                        content: Text('Are you sure you want to delete "${t.title}"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.error,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Yes, Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return confirmed == true;
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(Icons.delete_rounded, color: Colors.white),
                                  ),
                                  onDismissed: (_) {
                                    todoProvider.deleteTodo(t.id);
                                    ScaffoldMessenger.of(context).clearSnackBars();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Deleted "${t.title}"'),
                                        duration: const Duration(milliseconds: 1800),
                                        behavior: SnackBarBehavior.floating,
                                        dismissDirection: DismissDirection.horizontal,
                                        onVisible: () {
                                          Future.delayed(const Duration(milliseconds: 1800), () {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                            }
                                          });
                                        },
                                      ),
                                    );
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Checkbox (missed items can't be completed, so none is shown)
                                          if (!isMissed) ...[
                                          Transform.scale(
                                            scale: 1.1,
                                            child: Checkbox(
                                              value: t.completed,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              activeColor: AppColors.success,
                                              onChanged: t.canComplete
                                                  ? (_) => todoProvider.toggleCompleted(t)
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ],

                                          // Details
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  t.title,
                                                  style: theme.textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                    decoration: t.completed ? TextDecoration.lineThrough : null,
                                                    color: t.completed
                                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                                                        : null,
                                                  ),
                                                ),
                                                if (t.description.isNotEmpty) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    t.description,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: theme.textTheme.bodySmall,
                                                  ),
                                                ],
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  children: [
                                                    // Missed / Overdue Tag
                                                    if (isMissed) ...[
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.error.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.error),
                                                            const SizedBox(width: 3),
                                                            Text(
                                                              isGoalsTab ? 'Overdue' : 'Missed',
                                                              style: const TextStyle(
                                                                fontSize: 10.5,
                                                                fontWeight: FontWeight.w800,
                                                                color: AppColors.error,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],

                                                    // Grace Period Tag (for Tasks)
                                                    if (inGrace) ...[
                                                      Builder(builder: (ctx) {
                                                        final remaining = t.absoluteDeadline!.difference(DateTime.now());
                                                        final hLeft = remaining.inHours;
                                                        final mLeft = remaining.inMinutes % 60;
                                                        final label = hLeft > 0
                                                            ? '⏳ ${hLeft}h ${mLeft}m left'
                                                            : '⏳ ${mLeft}m left';
                                                        return Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.orange.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                                                          ),
                                                          child: Text(
                                                            label,
                                                            style: const TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.orange,
                                                            ),
                                                          ),
                                                        );
                                                      }),
                                                    ],

                                                    // Category Tag
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        t.category,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                        ),
                                                      ),
                                                    ),

                                                    // Priority Tag
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: priority.$2.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        priority.$1,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w600,
                                                          color: priority.$2,
                                                        ),
                                                      ),
                                                    ),

                                                  ],
                                                ),
                                                // Deadline timeline (Goals only)
                                                if (t.isGoal && t.dueDate != null) ...[
                                                  const SizedBox(height: 10),
                                                  _GoalTimeline(goal: t),
                                                ],
                                                const SizedBox(height: 6),

                                                // Due Date & Time
                                                if (t.dueDate != null)
                                                  Text(
                                                    (t.dueDate!.hour != 0 || t.dueDate!.minute != 0)
                                                        ? 'Due: ${DateFormat('MMM d, yyyy h:mm a').format(t.dueDate!)}'
                                                        : 'Due: ${DateFormat('MMM d, yyyy').format(t.dueDate!)}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isMissed
                                                          ? AppColors.error
                                                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                                      fontWeight: isMissed ? FontWeight.w600 : FontWeight.normal,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),

                                          // Trailing Actions (Edit / Track)
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, size: 18),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () async {
                                                  final updated = await TodoForm.show(context, initial: t);
                                                  if (updated != null) {
                                                    await todoProvider.updateTodo(updated);
                                                  }
                                                },
                                              ),
                                              if (t.isTask) ...[
                                              const SizedBox(height: 8),
                                              Consumer<TaskTrackerProvider>(
                                                builder: (context, tracker, _) {
                                                  final isTracking = tracker.activeTodo?.id == t.id;
                                                  return IconButton(
                                                    icon: Icon(
                                                      isTracking ? Icons.stop_circle_rounded : Icons.play_circle_outline_rounded,
                                                      color: isTracking ? AppColors.error : AppColors.primary,
                                                      size: 24,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: () {
                                                      if (isTracking) {
                                                        tracker.finish(context);
                                                      } else {
                                                        tracker.startTracking(t);
                                                      }
                                                    },
                                                  );
                                                },
                                              ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of a goal's window (creation → deadline) has passed, with a
/// "days left" label, so long-horizon goals show where they stand.
class _GoalTimeline extends StatelessWidget {
  final Todo goal;
  const _GoalTimeline({required this.goal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = goal;
    final due = g.dueDate!;
    final now = DateTime.now();

    final start = g.createdAt ?? g.updatedAt;
    final total = due.difference(start).inMinutes;
    final passed = now.difference(start).inMinutes;
    final elapsed = g.completed
        ? 1.0
        : total <= 0
            ? 1.0
            : (passed / total).clamp(0.0, 1.0);

    final days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final String timeLeft;
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

    // Green until 25% or less of the goal's time remains (or it's overdue).
    final color = !g.completed && (g.isMissed || elapsed >= 0.75)
        ? AppColors.error
        : AppColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Timeline',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            Text(
              timeLeft,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: elapsed,
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}
