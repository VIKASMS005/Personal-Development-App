import 'package:flutter/material.dart';
import '../../models/timetable_slot.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_time_picker.dart';

class TimetableFormDialog extends StatefulWidget {
  final TimetableSlot? initial;
  final String defaultDay;

  const TimetableFormDialog({
    super.key,
    this.initial,
    this.defaultDay = 'Daily',
  });

  static Future<TimetableSlot?> show(
    BuildContext context, {
    TimetableSlot? initial,
    String defaultDay = 'Daily',
  }) {
    return showDialog<TimetableSlot>(
      context: context,
      builder: (_) => TimetableFormDialog(initial: initial, defaultDay: defaultDay),
    );
  }

  @override
  State<TimetableFormDialog> createState() => _TimetableFormDialogState();
}

class _TimetableFormDialogState extends State<TimetableFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  late String _dayOfWeek;
  late String _startTime;
  late String _endTime;
  late String _category;
  late bool _hasReminder;

  static const _days = [
    'Daily',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const _categories = [
    ('Study', Icons.menu_book_rounded, AppColors.tasks),
    ('Work', Icons.work_rounded, AppColors.secondary),
    ('Health', Icons.spa_rounded, AppColors.habits),
    ('Workout', Icons.fitness_center_rounded, AppColors.error),
    ('Leisure', Icons.sports_esports_rounded, AppColors.accent),
    ('Sleep', Icons.bedtime_rounded, AppColors.journal),
    ('Personal', Icons.person_rounded, AppColors.timetable),
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _titleCtrl = TextEditingController(text: init?.title ?? '');
    _descCtrl = TextEditingController(text: init?.description ?? '');
    _dayOfWeek = init?.dayOfWeek ?? (widget.defaultDay == 'All' ? 'Daily' : widget.defaultDay);
    _startTime = init?.startTime ?? '08:00 AM';
    _endTime = init?.endTime ?? '09:00 AM';
    _category = init?.category ?? 'Study';
    _hasReminder = init?.hasReminder ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.now(),
      helpText: isStart ? 'Select Start Time (AM / PM)' : 'Select End Time (AM / PM)',
    );
    if (picked != null && mounted) {
      final formatted = AppTimePicker.format(context, picked);
      setState(() {
        if (isStart) {
          _startTime = formatted;
        } else {
          _endTime = formatted;
        }
      });
    }
  }

  int _getCategoryColor(String cat) {
    switch (cat) {
      case 'Study':
        return 0xFF3B82F6;
      case 'Work':
        return 0xFF6366F1;
      case 'Health':
        return 0xFF10B981;
      case 'Workout':
        return 0xFFEF4444;
      case 'Leisure':
        return 0xFFF59E0B;
      case 'Sleep':
        return 0xFF8B5CF6;
      default:
        return 0xFF06B6D4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
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
                    isEdit ? 'Edit Routine Slot' : 'Add Routine Slot',
                    style: theme.textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Day of Week selector
              DropdownButtonFormField<String>(
                initialValue: _dayOfWeek,
                decoration: const InputDecoration(
                  labelText: 'Day / Frequency',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                ),
                items: _days
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => _dayOfWeek = v!),
              ),
              const SizedBox(height: 14),
              // Title
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Routine Title',
                  hintText: 'e.g. Deep Study, Workout, Team Meeting',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 14),
              // Description
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 14),
              // Time Range Pickers
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_rounded, size: 18),
                      label: Text(_startTime),
                      onPressed: () => _pickTime(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('to'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_filled_rounded, size: 18),
                      label: Text(_endTime),
                      onPressed: () => _pickTime(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Category Selector
              Text('Category', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((cat) {
                  final isSelected = _category == cat.$1;
                  return ChoiceChip(
                    avatar: Icon(cat.$2, size: 16, color: isSelected ? Colors.white : cat.$3),
                    label: Text(cat.$1),
                    selected: isSelected,
                    selectedColor: cat.$3,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : null,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _category = cat.$1);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              // Reminder Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Slot Reminder'),
                subtitle: const Text('Notify when this routine starts'),
                value: _hasReminder,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _hasReminder = v),
              ),
              const SizedBox(height: 20),
              // Actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: Text(isEdit ? 'Save Changes' : 'Add to Timetable'),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final slot = TimetableSlot(
                        id: widget.initial?.id,
                        dayOfWeek: _dayOfWeek,
                        startTime: _startTime,
                        endTime: _endTime,
                        title: _titleCtrl.text.trim(),
                        description: _descCtrl.text.trim(),
                        category: _category,
                        colorHex: _getCategoryColor(_category),
                        hasReminder: _hasReminder,
                      );
                      Navigator.pop(context, slot);
                    }
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
