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
    (1, 'Urgent & Important (Do First)', AppColors.error),
    (2, 'Important, Not Urgent (Schedule)', AppColors.warning),
    (3, 'Urgent, Not Important (Delegate)', AppColors.secondary),
    (4, 'Low Priority (Eliminate/Later)', AppColors.lightTextSecondary),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _titleC = TextEditingController(text: t?.title ?? '');
    _descC = TextEditingController(text: t?.description ?? '');
    _category = t?.category ?? 'General';
    _priority = t?.priority ?? 4;
    _due = t?.dueDate;
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
    }

    final t = Todo(
      id: widget.initial?.id,
      title: _titleC.text.trim(),
      description: _descC.text.trim(),
      category: _category,
      dueDate: _due,
      reminderDateTime: fullReminder,
      priority: _priority,
      timeSpentSeconds: widget.initial?.timeSpentSeconds ?? 0,
      targetMinutes: widget.initial?.targetMinutes ?? 0,
      completed: widget.initial?.completed ?? false,
    );
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final theme = Theme.of(context);

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
                  isEdit ? 'Edit Task' : 'Add New Task',
                  style: theme.textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleC,
              decoration: const InputDecoration(
                labelText: 'Task Title *',
                prefixIcon: Icon(Icons.task_alt_rounded),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Please enter a task title'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descC,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 14),

            // Category Selector
            Text('Task Category', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: _categoryOptions.map((c) {
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

            // Due Date
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(_due == null
                  ? 'Set Due Date'
                  : 'Due: ${DateFormat('MMM d, yyyy').format(_due!)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _due ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _due = d);
              },
            ),
            const SizedBox(height: 16),

            // Reminder Prompt Switch
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _enableReminder
                      ? AppColors.alarm.withValues(alpha: 0.4)
                      : theme.dividerColor,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            color: _enableReminder
                                ? AppColors.alarm
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Remind me about this task',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text(
                                'Schedule notification alert',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch(
                        value: _enableReminder,
                        activeThumbColor: AppColors.alarm,
                        onChanged: (val) {
                          setState(() {
                            _enableReminder = val;
                            if (val && _reminderDate == null) {
                              _reminderDate = _due ?? DateTime.now();
                              _reminderTime = TimeOfDay(
                                  hour: (DateTime.now().hour + 1) % 24,
                                  minute: 0);
                            }
                          });
                        },
                      ),
                    ],
                  ),

                  // If Reminder Enabled: Show Date & Time Picker Row
                  if (_enableReminder) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _reminderDate ?? DateTime.now(),
                                firstDate: DateTime.now()
                                    .subtract(const Duration(days: 1)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (d != null) setState(() => _reminderDate = d);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.alarm.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today_rounded,
                                      size: 16, color: AppColors.alarm),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _reminderDate != null
                                          ? DateFormat('MMM d')
                                              .format(_reminderDate!)
                                          : 'Select Date',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final t = await AppTimePicker.show(
                                context,
                                initialTime: _reminderTime ?? TimeOfDay.now(),
                                helpText: 'Task Reminder Time (AM / PM)',
                              );
                              if (t != null) setState(() => _reminderTime = t);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.alarm.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_rounded,
                                      size: 16, color: AppColors.alarm),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _reminderTime != null
                                          ? AppTimePicker.format(context, _reminderTime!)
                                          : 'Select Time (AM/PM)',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: Text(isEdit ? 'Save Task' : 'Create Task'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.tasks,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
