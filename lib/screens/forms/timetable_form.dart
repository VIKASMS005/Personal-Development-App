import 'package:flutter/material.dart';
import '../../models/timetable_slot.dart';
import '../../utils/app_time_picker.dart';
import '../../widgets/ds/ds.dart';

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
    return showModalBottomSheet<TimetableSlot>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
    ('Study', Icons.menu_book_rounded),
    ('Work', Icons.work_outline_rounded),
    ('Health', Icons.spa_outlined),
    ('Workout', Icons.fitness_center_rounded),
    ('Leisure', Icons.sports_esports_outlined),
    ('Sleep', Icons.bedtime_outlined),
    ('Personal', Icons.person_outline_rounded),
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
      helpText: isStart ? 'Start time' : 'End time',
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

  void _save() {
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
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final categories = _categories.any((c) => c.$1 == _category) ? _categories : [..._categories, (_category, Icons.event_note_outlined)];
    final days = _days.contains(_dayOfWeek) ? _days : [..._days, _dayOfWeek];

    return SheetScaffold(
      title: isEdit ? 'Edit time block' : 'New time block',
      footer: FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
        child: Text(isEdit ? 'Save changes' : 'Add to timetable'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Deep study',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: PickerField(label: 'Starts', value: _startTime, icon: Icons.schedule_rounded, onTap: () => _pickTime(true))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: PickerField(label: 'Ends', value: _endTime, icon: Icons.schedule_rounded, onTap: () => _pickTime(false))),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Repeats'),
            ChoiceWrap<String>(
              options: days,
              selected: _dayOfWeek,
              labelOf: (d) => d == 'Daily' ? 'Every day' : d.substring(0, 3),
              onSelected: (d) => setState(() => _dayOfWeek = d),
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Category'),
            ChoiceWrap<(String, IconData)>(
              options: categories,
              selected: categories.firstWhere((c) => c.$1 == _category),
              labelOf: (c) => c.$1,
              iconOf: (c) => c.$2,
              onSelected: (c) => setState(() => _category = c.$1),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remind me'),
              subtitle: const Text('Get a notification when this block starts'),
              value: _hasReminder,
              onChanged: (v) => setState(() => _hasReminder = v),
            ),
          ],
        ),
      ),
    );
  }
}
