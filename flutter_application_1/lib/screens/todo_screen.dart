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
  int _selectedStatusFilter = 0; // 0=Scheduled, 1=Completed, 2=Missed, 3=All
  int _selectedPriorityFilter = 0; // 0=All, 1=Q1, 2=Q2, 3=Q3, 4=Q4
  String _searchQuery = '';

  static const _priorityLabels = {
    1: ('Q1: Urgent & Important', AppColors.error),
    2: ('Q2: Important', AppColors.warning),
    3: ('Q3: Delegate', AppColors.secondary),
    4: ('Q4: Low Priority', AppColors.lightTextSecondary),
  };

  String _formatTrackedTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final todoProvider = context.watch<TodoProvider>();

    final now = DateTime.now();

    final scheduledTasks = todoProvider.todos.where((t) {
      if (t.completed) return false;
      // Missed = dueDate is in the past. So scheduled = NOT missed.
      final isOverdue = t.dueDate != null && t.dueDate!.isBefore(now);
      return !isOverdue;
    }).toList();

    final completedTasks = todoProvider.todos.where((t) => t.completed).toList();

    final missedTasks = todoProvider.todos.where((t) {
      if (t.completed) return false;
      // Only dueDate past = missed. reminderDateTime past is NOT missed.
      return t.dueDate != null && t.dueDate!.isBefore(now);
    }).toList();

    final allTasks = todoProvider.todos;

    final statusFilters = [
      'Scheduled (${scheduledTasks.length})',
      'Completed (${completedTasks.length})',
      'Missed (${missedTasks.length})',
      'All (${allTasks.length})',
    ];

    final priorityFilters = [
      'All Priorities',
      '🚨 Q1 Urgent',
      '⭐ Q2 Important',
      '⚡ Q3 Delegate',
      '🌱 Q4 Low',
    ];

    List<Todo> sourceList;
    switch (_selectedStatusFilter) {
      case 0:
        sourceList = scheduledTasks;
        break;
      case 1:
        sourceList = completedTasks;
        break;
      case 2:
        sourceList = missedTasks;
        break;
      case 3:
      default:
        sourceList = allTasks;
        break;
    }

    List<Todo> filtered = sourceList.where((t) {
      if (_searchQuery.isNotEmpty) {
        if (!t.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
            !t.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      if (_selectedPriorityFilter > 0) {
        if (t.priority != _selectedPriorityFilter) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks and Goals'),
        actions: [
          IconButton(
            tooltip: 'Task Reports & Analytics',
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
        backgroundColor: AppColors.tasks,
        foregroundColor: Colors.white,
        onPressed: () async {
          final t = await TodoForm.show(context);
          if (t != null && auth.uid != null) {
            t.uid = auth.uid!;
            await todoProvider.addTodo(t);
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          // Non-blocking tracker bar if active
          const GlobalTaskTrackerBar(),

          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: [
                    // 1. Search Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search tasks and goals...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 18),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                )
                              : null,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),

                    // 2. Primary Status Filter Tabs: Scheduled -> Completed -> Missed -> All
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: statusFilters.length,
                        itemBuilder: (context, i) {
                          final isSelected = _selectedStatusFilter == i;
                          final isMissedTab = i == 2;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(statusFilters[i]),
                              selected: isSelected,
                              selectedColor: isMissedTab
                                  ? AppColors.error.withValues(alpha: 0.2)
                                  : AppColors.tasks.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? (isMissedTab
                                        ? AppColors.error
                                        : AppColors.tasks)
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                fontSize: 12,
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedStatusFilter = i),
                            ),
                          );
                        },
                      ),
                    ),

                    // 3. Priority Filter Pills (Q1 to Q4)
                    SizedBox(
                      height: 38,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: priorityFilters.length,
                        itemBuilder: (context, i) {
                          final isSelected = _selectedPriorityFilter == i;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(
                                priorityFilters[i],
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              ),
                              selected: isSelected,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 0),
                              onSelected: (_) =>
                                  setState(() => _selectedPriorityFilter = i),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 4. Task List View
                    Expanded(
                      child: filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.task_alt_rounded,
                              title: _selectedStatusFilter == 0
                                  ? 'No Scheduled Tasks'
                                  : _selectedStatusFilter == 1
                                      ? 'No Completed Tasks Yet'
                                      : _selectedStatusFilter == 2
                                          ? 'No Missed Deadlines!'
                                          : 'No Tasks Found',
                              subtitle: _selectedStatusFilter == 2
                                  ? 'Great job keeping up with all your deadlines!'
                                  : 'Tap the + button to add a new task or goal.',
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 6, 16, 80),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final t = filtered[i];
                                final priority = _priorityLabels[t.priority] ??
                                    ('Normal', AppColors.primary);
                                // Use model-level isMissed (2-hour grace period)
                                final isMissed = t.isMissed;
                                final inGrace = t.isInGracePeriod;

                                return Dismissible(
                                  key: Key(t.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(Icons.delete_rounded,
                                        color: Colors.white),
                                  ),
                                  onDismissed: (_) {
                                    todoProvider.deleteTodo(t.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Deleted "${t.title}"'),
                                        action: SnackBarAction(
                                          label: 'UNDO',
                                          onPressed: () =>
                                              todoProvider.addTodo(t),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Checkbox — disabled when permanently missed
                                          Transform.scale(
                                            scale: 1.1,
                                            child: Checkbox(
                                              value: t.completed,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              activeColor: AppColors.success,
                                              onChanged: t.canComplete
                                                  ? (_) => todoProvider.toggleCompleted(t)
                                                  : null, // disabled after grace period
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          // Task Details
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  t.title,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    fontSize: 15,
                                                    decoration: t.completed
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : null,
                                                    color: t.completed
                                                        ? theme
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: 0.45)
                                                        : null,
                                                  ),
                                                ),
                                                if (t.description
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    t.description,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall,
                                                  ),
                                                ],
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                   children: [
                                                    // Permanently Missed Tag
                                                    if (isMissed) ...[
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppColors.error
                                                              .withValues(
                                                                  alpha: 0.15),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          border: Border.all(
                                                              color: AppColors
                                                                  .error
                                                                  .withValues(
                                                                      alpha:
                                                                          0.4)),
                                                        ),
                                                        child: const Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                                Icons
                                                                    .warning_amber_rounded,
                                                                size: 12,
                                                                color: AppColors
                                                                    .error),
                                                            SizedBox(width: 3),
                                                            Text(
                                                              'Missed',
                                                              style: TextStyle(
                                                                fontSize: 10.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: AppColors
                                                                    .error,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],

                                                    // Grace Period Tag — shown when in 2h window after due
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

                                                    // Priority Badge
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: priority.$2
                                                            .withValues(
                                                                alpha: 0.12),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Text(
                                                        priority.$1,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: priority.$2,
                                                        ),
                                                      ),
                                                    ),

                                                    // Category Chip
                                                    if (t.category.isNotEmpty &&
                                                        t.category !=
                                                            'General')
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppColors
                                                              .primary
                                                              .withValues(
                                                                  alpha: 0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Text(
                                                          t.category,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppColors
                                                                .primary,
                                                          ),
                                                        ),
                                                      ),

                                                    // Non-Blocking Background Track Time Button
                                                    InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      onTap: () {
                                                        context
                                                            .read<
                                                                TaskTrackerProvider>()
                                                            .startTracking(t);
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Row(
                                                              children: [
                                                                const Icon(
                                                                    Icons
                                                                        .timer_rounded,
                                                                    color: Colors
                                                                        .white),
                                                                const SizedBox(
                                                                    width: 10),
                                                                Expanded(
                                                                  child: Text(
                                                                      '⏱️ Focus timer running in background for "${t.title}"'),
                                                                ),
                                                              ],
                                                            ),
                                                            backgroundColor:
                                                                AppColors.tasks,
                                                            duration:
                                                                const Duration(
                                                                    seconds: 3),
                                                          ),
                                                        );
                                                      },
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppColors.tasks
                                                              .withValues(
                                                                  alpha: 0.12),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          border: Border.all(
                                                            color: AppColors
                                                                .tasks
                                                                .withValues(
                                                                    alpha: 0.3),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .play_arrow_rounded,
                                                                size: 14,
                                                                color: AppColors
                                                                    .tasks),
                                                            const SizedBox(
                                                                width: 2),
                                                            Text(
                                                              t.timeSpentSeconds >
                                                                      0
                                                                  ? _formatTrackedTime(
                                                                      t.timeSpentSeconds)
                                                                  : 'Track Time',
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: AppColors
                                                                    .tasks,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),

                                                    // Due Date + Time
                                                    if (t.dueDate != null) ...[
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.calendar_today_rounded,
                                                            size: 11,
                                                            color: isMissed
                                                                ? AppColors.error
                                                                : inGrace
                                                                    ? Colors.orange
                                                                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                                          ),
                                                          const SizedBox(width: 3),
                                                          Text(
                                                            () {
                                                              final d = t.dueDate!;
                                                              final hasTime = d.hour != 0 || d.minute != 0;
                                                              return hasTime
                                                                  ? DateFormat('MMM d, yyyy h:mm a').format(d)
                                                                  : DateFormat('MMM d, yyyy').format(d);
                                                            }(),
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w600,
                                                              color: isMissed
                                                                  ? AppColors.error
                                                                  : inGrace
                                                                      ? Colors.orange
                                                                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Edit Button
                                          IconButton(
                                            icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18),
                                            onPressed: () async {
                                              final updated =
                                                  await TodoForm.show(
                                                      context, initial: t);
                                              if (updated != null) {
                                                todoProvider
                                                    .updateTodo(updated);
                                              }
                                            },
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
