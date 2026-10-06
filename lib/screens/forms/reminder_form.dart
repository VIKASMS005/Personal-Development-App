import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/reminder.dart';
import '../../utils/app_time_picker.dart';
import '../../services/notification_service.dart';
import '../../widgets/ds/ds.dart';

class ReminderForm extends StatefulWidget {
  final Reminder? initialReminder;
  final DateTime? initialDate;

  const ReminderForm({
    super.key,
    this.initialReminder,
    this.initialDate,
  });

  static Future<Reminder?> show(
    BuildContext context, {
    Reminder? reminder,
    DateTime? defaultDate,
  }) {
    return showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReminderForm(
        initialReminder: reminder,
        initialDate: defaultDate,
      ),
    );
  }

  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _selectedCategory = 'Personal';

  final List<String> _categories = [
    'Personal',
    'Work',
    'Study',
    'Health',
    'Urgent',
  ];

  @override
  void initState() {
    super.initState();
    final rem = widget.initialReminder;
    _titleCtrl = TextEditingController(text: rem?.title ?? '');
    _descCtrl = TextEditingController(text: rem?.description ?? '');
    _selectedDate = rem?.dateTime ?? widget.initialDate ?? DateTime.now();
    _selectedTime = rem != null
        ? TimeOfDay.fromDateTime(rem.dateTime)
        : TimeOfDay(hour: (DateTime.now().hour + 1) % 24, minute: 0);
    if (rem != null) {
      _selectedCategory = rem.category;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await AppTimePicker.show(
      context,
      initialTime: _selectedTime,
      helpText: 'Reminder time',
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await NotificationService.requestPermissions();

    final fullDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final reminder = Reminder(
      id: widget.initialReminder?.id,
      uid: widget.initialReminder?.uid ?? 'local_user',
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      dateTime: fullDateTime,
      category: _selectedCategory,
      isCompleted: widget.initialReminder?.isCompleted ?? false,
    );

    if (mounted) {
      Navigator.pop(context, reminder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialReminder != null;
    final when = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final inPast = when.isBefore(DateTime.now());

    return SheetScaffold(
      title: isEdit ? 'Edit reminder' : 'New reminder',
      footer: FilledButton(
        onPressed: _submit,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
        child: Text(isEdit ? 'Save changes' : 'Set reminder'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleCtrl,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Drink water, call John',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Give the reminder a short title';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descCtrl,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('When'),
            Row(
              children: [
                Expanded(
                  child: PickerField(
                    label: 'Date',
                    icon: Icons.calendar_today_outlined,
                    value: DateFormat('EEE, d MMM').format(_selectedDate),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PickerField(
                    label: 'Time',
                    icon: Icons.schedule_rounded,
                    value: AppTimePicker.format(context, _selectedTime),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            if (inPast) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This time has already passed. Pick a later time to get notified.',
                style: context.text.labelSmall?.copyWith(color: context.colors.warning),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Category'),
            ChoiceWrap<String>(
              options: _categories,
              selected: _categories.contains(_selectedCategory) ? _selectedCategory : _categories.first,
              labelOf: (c) => c,
              iconOf: categoryIcon,
              onSelected: (c) => setState(() => _selectedCategory = c),
            ),
          ],
        ),
      ),
    );
  }
}
