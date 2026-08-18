import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';
import '../models/todo.dart';
import '../utils/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_card.dart';
import '../widgets/task_timer_dialog.dart';
import 'forms/todo_form.dart';
import 'task_report_screen.dart';

class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  int _selectedFilter = 0; // 0=All, 1=Q1, 2=Q2, 3=Q3, 4=Q4, 5=Missed, 6=Done
  String _searchQuery = '';

  static const _priorityLabels = {
    1: ('Urgent & Important', AppColors.error),
    2: ('Important', AppColors.warning),
    3: ('Urgent', AppColors.secondary),
    4: ('Low Priority', AppColors.lightTextSecondary),
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

    final filters = [
      'All',
      '🚨 Q1 Urgent',
      '⭐ Q2 Important',
      '⚡ Q3 Delegate',
      '🌱 Q4 Low',
      '⏰ Missed (${todoProvider.missedCount})',
      '✓ Completed',
    ];

    List<Todo> filtered = todoProvider.todos.where((t) {
      if (_searchQuery.isNotEmpty) {
        if (!t.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
            !t.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }
      final now = DateTime.now();
      final isMissed = !t.completed &&
          ((t.dueDate != null && t.dueDate!.isBefore(now)) ||
              (t.reminderDateTime != null && t.reminderDateTime!.isBefore(now)));

      if (_selectedFilter == 0) return true;
      if (_selectedFilter == 1) return t.priority == 1 && !t.completed;
      if (_selectedFilter == 2) return t.priority == 2 && !t.completed;
      if (_selectedFilter == 3) return t.priority == 3 && !t.completed;
      if (_selectedFilter == 4) return t.priority == 4 && !t.completed;
      if (_selectedFilter == 5) return isMissed;
      if (_selectedFilter == 6) return t.completed;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & Matrix'),
        actions: [
          IconButton(
            tooltip: 'Task Reports & Analytics',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.tasks.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.insights_rounded, color: AppColors.tasks, size: 20),
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // 1. Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
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

              // 2. Matrix Filter Chips
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filters.length,
                  itemBuilder: (context, i) {
                    final isSelected = _selectedFilter == i;
                    final isMissedFilter = i == 5;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filters[i]),
                        selected: isSelected,
                        selectedColor: isMissedFilter ? AppColors.error : AppColors.tasks,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isMissedFilter && todoProvider.missedCount > 0 ? AppColors.error : null),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _selectedFilter = i);
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // 3. Task List
              Expanded(
                child: filtered.isEmpty
                    ? EmptyState(
                        icon: _selectedFilter == 5 ? Icons.alarm_off_rounded : Icons.task_alt_rounded,
                        title: _selectedFilter == 5 ? 'No missed tasks' : 'No tasks found',
                        subtitle: _selectedFilter == 5
                            ? 'Great job! You have no overdue or missed deadlines.'
                            : 'Tap + to create a task for this matrix quadrant',
                        iconColor: _selectedFilter == 5 ? AppColors.success : AppColors.tasks,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final t = filtered[index];
                          final priority = _priorityLabels[t.priority] ??
                              ('Normal', AppColors.lightTextSecondary);
                          final now = DateTime.now();
                          final isMissed = !t.completed &&
                              ((t.dueDate != null && t.dueDate!.isBefore(now)) ||
                                  (t.reminderDateTime != null && t.reminderDateTime!.isBefore(now)));

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
                              child: const Icon(Icons.delete_outline,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) {
                              todoProvider.deleteTodo(t.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Deleted "${t.title}"'),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () => todoProvider.addTodo(t),
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AppCard(
                                accentColor: isMissed ? AppColors.error : priority.$2,
                                onTap: () async {
                                  final edited = await TodoForm.show(context, initial: t);
                                  if (edited != null) {
                                    await todoProvider.updateTodo(edited);
                                  }
                                },
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: t.completed,
                                      activeColor: AppColors.tasks,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      onChanged: (_) {
                                        todoProvider.toggleCompleted(t);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.title,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              decoration: t.completed
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: t.completed
                                                  ? theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.45)
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
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              // Missed Tag if overdue
                                              if (isMissed) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.error),
                                                      SizedBox(width: 3),
                                                      Text(
                                                        'Missed Deadline',
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: AppColors.error,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              // Priority Badge
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: priority.$2.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  priority.$1,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: priority.$2,
                                                  ),
                                                ),
                                              ),

                                              // Category Chip
                                              if (t.category.isNotEmpty && t.category != 'General')
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    t.category,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                ),

                                              // Interactive Track Time Chip
                                              InkWell(
                                                borderRadius: BorderRadius.circular(8),
                                                onTap: () => TaskTimerDialog.show(context, t),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.tasks.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: AppColors.tasks.withValues(alpha: 0.3),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.timer_outlined, size: 12, color: AppColors.tasks),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        t.timeSpentSeconds > 0
                                                            ? _formatTrackedTime(t.timeSpentSeconds)
                                                            : 'Track Time',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w800,
                                                          color: AppColors.tasks,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),

                                              // Due Date
                                              if (t.dueDate != null) ...[
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.schedule,
                                                      size: 13,
                                                      color: theme.colorScheme.onSurface
                                                          .withValues(alpha: 0.5),
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      t.dueDate!
                                                          .toLocal()
                                                          .toString()
                                                          .split(' ')[0],
                                                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                              ],

                                              // Reminder time
                                              if (t.reminderDateTime != null) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.alarm.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.notifications_active_rounded, size: 11, color: AppColors.alarm),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        '${t.reminderDateTime!.hour.toString().padLeft(2, '0')}:${t.reminderDateTime!.minute.toString().padLeft(2, '0')}',
                                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.alarm),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Quick Live Timer Launch Button
                                    IconButton(
                                      tooltip: 'Start Live Timer',
                                      icon: const Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: AppColors.tasks,
                                        size: 26,
                                      ),
                                      onPressed: () => TaskTimerDialog.show(context, t),
                                    ),

                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppColors.error.withValues(alpha: 0.7),
                                      ),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Delete Task'),
                                            content: const Text('Are you sure you want to delete this task?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(context, true),
                                                child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await todoProvider.deleteTodo(t.id);
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
    );
  }
}
