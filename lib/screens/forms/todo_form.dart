import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/todo.dart';
import '../../utils/app_time_picker.dart';
import '../../widgets/ds/ds.dart';

class TodoForm extends StatefulWidget {
  final Todo? initial;
  const TodoForm({super.key, this.initial});

  static Future<Todo?> show(BuildContext context, {Todo? initial}) => showModalBottomSheet<Todo?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => TodoForm(initial: initial),
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
    'General',
    'Study',
    'Work',
    'Coding',
    'Fitness',
    'Reading',
    'Personal',
    'Other',
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
      _reminderTime = TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
    }
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  DateTime? get _fullReminder {
    if (_enableReminder && _reminderDate != null && _reminderTime != null) {
      return DateTime(
        _reminderDate!.year,
        _reminderDate!.month,
        _reminderDate!.day,
        _reminderTime!.hour,
        _reminderTime!.minute,
      );
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final initialType = widget.initial?.type;
    final finalType = initialType ?? Todo.classify(dueDate: _due, createdAt: DateTime.now());

    final t = Todo(
      id: widget.initial?.id,
      uid: widget.initial?.uid ?? 'local_user',
      title: _titleC.text.trim(),
      description: _descC.text.trim(),
      category: _category,
      dueDate: _due,
      reminderDateTime: _fullReminder,
      priority: _priority,
      timeSpentSeconds: widget.initial?.timeSpentSeconds ?? 0,
      targetMinutes: widget.initial?.targetMinutes ?? 0,
      completed: widget.initial?.completed ?? false,
      type: finalType,
      createdAt: widget.initial?.createdAt ?? DateTime.now(),
    );
    Navigator.pop(context, t);
  }

  Future<void> _pickDueDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (d != null) {
      setState(() {
        final existingTime = _dueTime;
        if (existingTime != null) {
          _due = DateTime(d.year, d.month, d.day, existingTime.hour, existingTime.minute);
        } else {
          _due = DateTime(d.year, d.month, d.day, 23, 59);
        }
      });
    }
  }

  Future<void> _pickDueTime() async {
    final t = await AppTimePicker.show(
      context,
      initialTime: _dueTime ?? const TimeOfDay(hour: 23, minute: 59),
      helpText: 'Due time',
    );
    if (t != null) {
      setState(() {
        _dueTime = t;
        final baseDate = _due ?? DateTime.now();
        _due = DateTime(baseDate.year, baseDate.month, baseDate.day, t.hour, t.minute);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;

    // The preview uses the same rule as saving, so what the user sees here is
    // exactly how the item will be classified.
    final isGoal = widget.initial != null
        ? widget.initial!.isGoal
        : Todo.classify(dueDate: _due, createdAt: DateTime.now()) == 'goal';
    final noun = isGoal ? 'goal' : 'task';
    final reminder = _fullReminder;
    final reminderInPast = reminder != null && reminder.isBefore(DateTime.now());

    return SheetScaffold(
      title: isEdit ? 'Edit $noun' : 'New task or goal',
      footer: FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
        child: Text(isEdit ? 'Save changes' : 'Add $noun'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleC,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Give it a short title' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descC,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),

            const FieldLabel('Due'),
            Row(
              children: [
                Expanded(
                  child: PickerField(
                    label: 'Date',
                    icon: Icons.calendar_today_outlined,
                    value: _due != null ? DateFormat('d MMM yyyy').format(_due!) : null,
                    placeholder: 'No date',
                    onTap: _pickDueDate,
                    onClear: () => setState(() {
                      _due = null;
                      _dueTime = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PickerField(
                    label: 'Time',
                    icon: Icons.schedule_rounded,
                    value: _dueTime == null ? null : AppTimePicker.format(context, _dueTime!),
                    placeholder: 'Any time',
                    onTap: _pickDueTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            InlineBanner(
              icon: isGoal ? Icons.flag_outlined : Icons.task_alt_rounded,
              tone: StatusTone.neutral,
              message: isEdit
                  ? 'Saved as a $noun. The type is fixed when an item is created.'
                  : isGoal
                      ? 'This will be a goal because the deadline is more than 7 days away.'
                      : 'This will be a task. Items due more than 7 days away become goals.',
            ),
            const SizedBox(height: AppSpacing.lg),

            const FieldLabel('Priority'),
            ChoiceWrap<PriorityStyle>(
              options: PriorityStyle.all,
              selected: PriorityStyle.of(_priority),
              labelOf: (p) => p.shortLabel,
              iconOf: (p) => p.icon,
              onSelected: (p) => setState(() => _priority = p.level),
            ),
            const SizedBox(height: AppSpacing.lg),

            const FieldLabel('Category'),
            ChoiceWrap<String>(
              options: _categoryOptions,
              selected: _categoryOptions.contains(_category) ? _category : 'Other',
              labelOf: (c) => c,
              iconOf: categoryIcon,
              onSelected: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: AppSpacing.md),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enableReminder,
              onChanged: (v) => setState(() => _enableReminder = v),
              title: const Text('Remind me'),
              subtitle: const Text('Get a notification at a set time'),
            ),
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: !_enableReminder
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: PickerField(
                                  label: 'Reminder date',
                                  icon: Icons.notifications_none_rounded,
                                  value: _reminderDate != null ? DateFormat('d MMM yyyy').format(_reminderDate!) : null,
                                  onTap: () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: _reminderDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (d != null) setState(() => _reminderDate = d);
                                  },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: PickerField(
                                  label: 'Time',
                                  icon: Icons.schedule_rounded,
                                  value: _reminderTime == null ? null : AppTimePicker.format(context, _reminderTime!),
                                  onTap: () async {
                                    final t = await AppTimePicker.show(
                                      context,
                                      initialTime: _reminderTime ?? TimeOfDay.now(),
                                      helpText: 'Reminder time',
                                    );
                                    if (t != null) setState(() => _reminderTime = t);
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (reminderInPast) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'This time has already passed. Pick a later time to get notified.',
                              style: context.text.labelSmall?.copyWith(color: context.colors.warning),
                            ),
                          ],
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
