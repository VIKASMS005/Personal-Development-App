import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/todo.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_time_picker.dart';

class TodoForm extends StatefulWidget {
  final Todo? initial;
  const TodoForm({super.key, this.initial});

  static Future<Todo?> show(BuildContext context, {Todo? initial}) =>
      showDialog<Todo?>(
        context: context,
        builder: (_) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: TodoForm(initial: initial),
        ),
      );

  @override
  State<TodoForm> createState() => _TodoFormState();
}

class _TodoFormState extends State<TodoForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleC;
  late TextEditingController _descC;
  String _category = 'General';
  int _priority = 4;
  DateTime? _due;
  TimeOfDay? _dueTime;
  bool _enableReminder = false;
  DateTime? _reminderDate;
  TimeOfDay? _reminderTime;

  static const _categoryOptions = [
    ('General', Icons.checklist_rounded),
    ('Study', Icons.menu_book_rounded),
    ('Work', Icons.work_rounded),
    ('Coding', Icons.code_rounded),
    ('Fitness', Icons.fitness_center_rounded),
    ('Reading', Icons.auto_stories_rounded),
    ('Personal', Icons.person_rounded),
    ('Other', Icons.category_rounded),
  ];

  static const _priorityOptions = [
    (1, 'Urgent', AppColors.error),
    (2, 'Important', AppColors.warning),
    (3, 'Medium Priority', AppColors.secondary),
    (4, 'Low Priority', AppColors.lightTextSecondary),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _titleC = TextEditingController(text: t?.title ?? '');
    _descC = TextEditingController(text: t?.description ?? '');
    _category = t?.category ?? 'General';
    _priority = (t?.priority ?? 4).clamp(1, 4);
    _due = t?.dueDate;
    if (t?.dueDate != null) {
      final d = t!.dueDate!;
      if (d.hour != 0 || d.minute != 0) {
        _dueTime = TimeOfDay(hour: d.hour, minute: d.minute);
      }
    }
    if (t?.reminderDateTime != null) {
      _enableReminder = true;
      _reminderDate = t!.reminderDateTime!;
      _reminderTime = TimeOfDay.fromDateTime(t.reminderDateTime!);
    } else {
      _reminderDate = DateTime.now();
      _reminderTime =
          TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
    }
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    DateTime? fullReminder;
    if (_enableReminder && _reminderDate != null && _reminderTime != null) {
      fullReminder = DateTime(
        _reminderDate!.year,
        _reminderDate!.month,
        _reminderDate!.day,
        _reminderTime!.hour,
        _reminderTime!.minute,
      );
      // A new or changed reminder must be in the future, or it never rings.
      if (fullReminder != widget.initial?.reminderDateTime &&
          !fullReminder.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick a reminder time in the future')),
        );
        return;
      }
    }

    final initialType = widget.initial?.type;
    final finalType = initialType ?? Todo.classify(dueDate: _due, createdAt: DateTime.now());

    final t = Todo(
      id: widget.initial?.id,
      uid: widget.initial?.uid ?? 'local_user',
      title: _titleC.text.trim(),
      description: _descC.text.trim(),
      category: _category,
      dueDate: _due,
      reminderDateTime: fullReminder,
      priority: _priority,
      timeSpentSeconds: widget.initial?.timeSpentSeconds ?? 0,
      targetMinutes: widget.initial?.targetMinutes ?? 0,
      completed: widget.initial?.completed ?? false,
      completedAt: widget.initial?.completedAt,
      type: finalType,
      createdAt: widget.initial?.createdAt ?? DateTime.now(),
    );
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final theme = Theme.of(context);

    final isGoal = widget.initial != null
        ? widget.initial!.isGoal
        // Same rule that will classify it on save.
        : Todo.classify(dueDate: _due, createdAt: DateTime.now()) == 'goal';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit
                      ? (widget.initial?.isGoal == true ? 'Edit Goal' : 'Edit Task')
                      : 'Add Task / Goal',
                  style: theme.textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title
            TextFormField(
              controller: _titleC,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title *',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 14),

            // Description
            TextFormField(
              controller: _descC,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.description_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Category Dropdown
            Text('Category', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.category_rounded),
              ),
              // Keep an unknown category (e.g. from an AI-made task) as an
              // item, or the dropdown asserts.
              items: [
                ..._categoryOptions,
                if (!_categoryOptions.any((c) => c.$1 == _category))
                  (_category, Icons.category_rounded),
              ].map((c) {
                return DropdownMenuItem(
                  value: c.$1,
                  child: Row(
                    children: [
                      Icon(c.$2, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(c.$1, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _category = v ?? 'General'),
            ),
            const SizedBox(height: 14),

            // Priority
            Text('Priority', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _priority,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.flag_rounded),
              ),
              items: _priorityOptions.map((p) {
                return DropdownMenuItem(
                  value: p.$1,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: p.$3),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.$2,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _priority = v ?? 4),
            ),
            const SizedBox(height: 14),

            // ── Due Date + Due Time ─────────────────────────────────────────
            Text('Due Date & Time', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                // Due Date
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      // The range must contain the current due date, or the
                      // picker fails when editing a task due long ago.
                      // A new task can't start out already overdue.
                      final now = DateTime.now();
                      final earliest = widget.initial == null
                          ? DateTime(now.year, now.month, now.day)
                          : now.subtract(const Duration(days: 30));
                      final first = _due != null && _due!.isBefore(earliest) ? _due! : earliest;
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _due ?? DateTime.now(),
                        firstDate: first,
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (d != null) {
                        setState(() {
                          final existingTime = _dueTime;
                          if (existingTime != null) {
                            _due = DateTime(d.year, d.month, d.day,
                                existingTime.hour, existingTime.minute);
                          } else {
                            _due = DateTime(d.year, d.month, d.day, 23, 59);
                          }
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: _due != null
                            ? AppColors.tasks.withValues(alpha: 0.1)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _due != null
                              ? AppColors.tasks.withValues(alpha: 0.4)
                              : theme.dividerColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_rounded, size: 16,
                              color: _due != null ? AppColors.tasks : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _due != null
                                  ? DateFormat('MMM d, yyyy').format(_due!)
                                  : 'Set Date',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _due != null ? null : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Due Time
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final t = await AppTimePicker.show(
                        context,
                        initialTime: _dueTime ?? const TimeOfDay(hour: 23, minute: 59),
                        helpText: 'Due Time',
                      );
                      if (t != null) {
                        setState(() {
                          _dueTime = t;
                          final baseDate = _due ?? DateTime.now();
                          _due = DateTime(baseDate.year, baseDate.month,
                              baseDate.day, t.hour, t.minute);
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: _dueTime != null
                            ? AppColors.tasks.withValues(alpha: 0.1)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _dueTime != null
                              ? AppColors.tasks.withValues(alpha: 0.4)
                              : theme.dividerColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 16,
                              color: _dueTime != null ? AppColors.tasks : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _dueTime != null
                                  ? _dueTime!.format(context)
                                  : 'Set Time',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _dueTime != null ? null : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_due != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    tooltip: 'Clear Due Date',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _due = null;
                      _dueTime = null;
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Classification indicator badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isGoal
                    ? AppColors.secondary.withValues(alpha: 0.12)
                    : AppColors.tasks.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isGoal
                      ? AppColors.secondary.withValues(alpha: 0.3)
                      : AppColors.tasks.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isGoal ? Icons.flag_rounded : Icons.task_alt_rounded,
                    size: 14,
                    color: isGoal ? AppColors.secondary : AppColors.tasks,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isGoal
                          ? 'Classified as Goal (Deadline > 7 days from creation)'
                          : 'Classified as Task (Deadline ≤ 7 days)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isGoal ? AppColors.secondary : AppColors.tasks,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Reminder Option ─────────────────────────────────────────────
            Row(
              children: [
                Checkbox(
                  value: _enableReminder,
                  activeColor: AppColors.tasks,
                  onChanged: (v) => setState(() => _enableReminder = v ?? false),
                ),
                Text('Set reminder notification',
                    style: theme.textTheme.bodyMedium),
              ],
            ),
            if (_enableReminder) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final r = _reminderDate ?? now;
                        final d = await showDatePicker(
                          context: context,
                          // A reminder that already passed opens on today.
                          initialDate: r.isBefore(DateTime(now.year, now.month, now.day)) ? now : r,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setState(() => _reminderDate = d);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.notifications_active_outlined,
                                size: 16),
                            const SizedBox(width: 8),
                            Text(
                              _reminderDate != null
                                  ? DateFormat('MMM d, yyyy')
                                      .format(_reminderDate!)
                                  : 'Select date',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final t = await AppTimePicker.show(
                          context,
                          initialTime: _reminderTime ?? TimeOfDay.now(),
                          helpText: 'Reminder Time',
                        );
                        if (t != null) setState(() => _reminderTime = t);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              _reminderTime != null
                                  ? _reminderTime!.format(context)
                                  : 'Select time',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isGoal ? AppColors.secondary : AppColors.tasks,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _save,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_rounded, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isEdit
                              ? (widget.initial?.isGoal == true ? 'Save Goal' : 'Save Task')
                              : (isGoal ? 'Add Goal' : 'Add Task'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
