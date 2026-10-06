import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_providers.dart';
import '../models/todo.dart';
import '../widgets/ds/ds.dart';
import '../widgets/global_task_tracker_bar.dart';
import '../widgets/todo_widgets.dart';
import 'forms/todo_form.dart';
import 'task_report_screen.dart';

class TodosScreen extends StatefulWidget {
  /// Open on the Goals tab instead of Tasks.
  final bool initialGoals;

  const TodosScreen({super.key, this.initialGoals = false});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  late int _selectedMainTab = widget.initialGoals ? 1 : 0; // 0=Tasks, 1=Goals
  int _selectedStatusFilter = 0; // 0=Scheduled/Active, 1=Completed, 2=Missed/Overdue, 3=All
  int _selectedPriorityFilter = 0; // 0=All, 1=Urgent&Important, 2=Important, 3=Urgent, 4=Low
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _add(AuthProvider auth, TodoProvider todoProvider) async {
    final t = await TodoForm.show(context);
    if (t != null && auth.uid != null) {
      t.uid = auth.uid!;
      await todoProvider.addTodo(t);
    }
  }

  Future<bool> _confirmDelete(Todo t) {
    return ConfirmDialog.show(
      context,
      title: t.isGoal ? 'Delete goal?' : 'Delete task?',
      message: '"${t.title}" will be removed. This can\'t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
  }

  void _afterDelete(TodoProvider todoProvider, Todo t) {
    todoProvider.deleteTodo(t.id);
    AppSnack.show(context, 'Deleted "${t.title}"');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final todoProvider = context.watch<TodoProvider>();

    final isGoalsTab = _selectedMainTab == 1;

    // Filter by permanent type
    final currentDomainList = isGoalsTab ? todoProvider.goals : todoProvider.tasks;

    final scheduledOrActive = isGoalsTab ? todoProvider.activeGoals : todoProvider.scheduledTasks;
    final completed = isGoalsTab ? todoProvider.completedGoals : todoProvider.completedTasks;
    final missedOrOverdue = isGoalsTab ? todoProvider.missedGoals : todoProvider.missedTasks;
    final all = currentDomainList;

    final statusFilters = [
      FilterOption(isGoalsTab ? 'Active' : 'Scheduled', count: scheduledOrActive.length),
      FilterOption('Completed', count: completed.length),
      FilterOption(isGoalsTab ? 'Overdue' : 'Missed', count: missedOrOverdue.length),
      FilterOption('All', count: all.length),
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

    final filtered = sourceList.where((t) {
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

    final noun = isGoalsTab ? 'goal' : 'task';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & goals'),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TaskReportScreen()),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(auth, todoProvider),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add $noun'),
      ),
      body: Column(
        children: [
          const GlobalTaskTrackerBar(),
          ContentWidth(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xxs, AppSpacing.screen, AppSpacing.sm),
                  child: AppSegmented<int>(
                    segments: {
                      0: 'Tasks · ${todoProvider.tasks.length}',
                      1: 'Goals · ${todoProvider.goals.length}',
                    },
                    icons: const {0: Icons.task_alt_rounded, 1: Icons.flag_outlined},
                    selected: _selectedMainTab,
                    onChanged: (v) => setState(() {
                      _selectedMainTab = v;
                      _selectedStatusFilter = 0;
                    }),
                  ),
                ),
                Padding(
                  padding: AppSpacing.screenPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search ${noun}s',
                            prefixIcon: const Icon(Icons.search_rounded, size: AppSizes.iconMd),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close_rounded, size: AppSizes.iconMd),
                                    onPressed: () => setState(() {
                                      _searchQuery = '';
                                      _searchController.clear();
                                    }),
                                  )
                                : null,
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _PriorityFilterButton(
                        value: _selectedPriorityFilter,
                        onChanged: (v) => setState(() => _selectedPriorityFilter = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                FilterBar(
                  options: statusFilters,
                  selectedIndex: _selectedStatusFilter,
                  onSelected: (i) => setState(() => _selectedStatusFilter = i),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.medium,
              child: filtered.isEmpty
                  ? _buildEmpty(isGoalsTab, auth, todoProvider)
                  : ContentWidth(
                      key: ValueKey('list-$_selectedMainTab-$_selectedStatusFilter'),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.screen, AppSpacing.xxs, AppSpacing.screen, AppSpacing.fabClearance),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _buildItem(filtered[i], todoProvider),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isGoalsTab, AuthProvider auth, TodoProvider todoProvider) {
    final filtering = _searchQuery.isNotEmpty || _selectedPriorityFilter > 0;
    String title;
    String subtitle;
    IconData icon = isGoalsTab ? Icons.flag_outlined : Icons.task_alt_rounded;
    if (filtering) {
      title = 'No matches';
      subtitle = 'Try a different search or priority filter.';
      icon = Icons.search_off_rounded;
    } else {
      switch (_selectedStatusFilter) {
        case 0:
          title = isGoalsTab ? 'No active goals' : 'No scheduled tasks';
          subtitle = isGoalsTab
              ? 'Goals are items with a deadline more than 7 days away.'
              : 'Tasks are items due within the next 7 days.';
          break;
        case 1:
          title = 'Nothing completed yet';
          subtitle = 'Completed ${isGoalsTab ? 'goals' : 'tasks'} will show up here.';
          break;
        case 2:
          title = isGoalsTab ? 'No overdue goals' : 'No missed tasks';
          subtitle = 'You\'re on track. Nice work.';
          icon = Icons.verified_outlined;
          break;
        default:
          title = isGoalsTab ? 'No goals yet' : 'No tasks yet';
          subtitle = 'Add your first ${isGoalsTab ? 'goal' : 'task'} to get started.';
      }
    }
    final showAdd = !filtering && _selectedStatusFilter != 2;
    return EmptyState(
      key: ValueKey('empty-$_selectedMainTab-$_selectedStatusFilter'),
      icon: icon,
      title: title,
      subtitle: subtitle,
      action: showAdd
          ? FilledButton.tonalIcon(
              onPressed: () => _add(auth, todoProvider),
              icon: const Icon(Icons.add_rounded, size: AppSizes.iconMd),
              label: Text(isGoalsTab ? 'Add goal' : 'Add task'),
            )
          : null,
    );
  }

  Widget _buildItem(Todo t, TodoProvider todoProvider) {
    final actions = Consumer<TaskTrackerProvider>(
      builder: (context, tracker, _) {
        final isTracking = tracker.activeTodo?.id == t.id;
        return TodoActions(
          isTracking: isTracking,
          onTrack: () {
            if (isTracking) {
              tracker.finish(context);
            } else {
              tracker.startTracking(t);
            }
          },
          onEdit: () async {
            final updated = await TodoForm.show(context, initial: t);
            if (updated != null) {
              await todoProvider.updateTodo(updated);
            }
          },
          onDelete: () async {
            if (await _confirmDelete(t) && mounted) _afterDelete(todoProvider, t);
          },
        );
      },
    );
    final onToggle = t.canComplete ? () => todoProvider.toggleCompleted(t) : null;

    return Dismissible(
      key: Key(t.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(t),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(color: context.colors.errorContainer, borderRadius: AppRadius.lgAll),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete', style: context.text.labelMedium?.copyWith(color: context.colors.error)),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.delete_outline_rounded, color: context.colors.error),
          ],
        ),
      ),
      onDismissed: (_) => _afterDelete(todoProvider, t),
      child: t.isGoal
          ? GoalProgressCard(goal: t, onToggle: onToggle, actions: actions)
          : TaskCard(todo: t, onToggle: onToggle, actions: actions),
    );
  }
}

class _PriorityFilterButton extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PriorityFilterButton({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final active = value > 0;
    final label = active ? PriorityStyle.of(value).shortLabel : 'Priority';
    return PopupMenuButton<int>(
      tooltip: 'Filter by priority',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        const PopupMenuItem(value: 0, child: Text('All priorities')),
        for (final p in PriorityStyle.all)
          PopupMenuItem(
            value: p.level,
            child: Row(
              children: [
                Icon(p.icon, size: AppSizes.iconMd, color: context.colors.toneColor(p.tone, context.scheme)),
                const SizedBox(width: AppSpacing.sm),
                Text(p.label),
              ],
            ),
          ),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: active ? context.scheme.primaryContainer : context.scheme.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: active ? context.scheme.primary.withValues(alpha: 0.35) : context.colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded,
                size: AppSizes.iconMd, color: active ? context.scheme.onPrimaryContainer : context.colors.textSecondary),
            const SizedBox(width: AppSpacing.xxs + 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(
                  color: active ? context.scheme.onPrimaryContainer : context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
