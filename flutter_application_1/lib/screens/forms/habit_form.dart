import 'package:flutter/material.dart';
import '../../models/habit.dart';

class HabitForm extends StatefulWidget {
  final Habit? initial;
  const HabitForm({super.key, this.initial});

  static Future<Habit?> show(BuildContext context, {Habit? initial}) {
    return showDialog<Habit?>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: HabitForm(initial: initial),
      ),
    );
  }

  @override
  State<HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<HabitForm> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _titleC;
  HabitFrequency _freq = HabitFrequency.daily;

  @override
  void initState() {
    super.initState();
    _titleC = TextEditingController(text: widget.initial?.title ?? '');
    _freq = widget.initial?.frequency ?? HabitFrequency.daily;
  }

  @override
  void dispose() {
    _titleC.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final h = Habit(
      id: widget.initial?.id,
      title: _titleC.text.trim(),
      frequency: _freq,
      history: widget.initial?.history,
      streak: widget.initial?.streak ?? 0,
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, h);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? 'Edit Habit' : 'Build New Habit',
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
                labelText: 'Habit Title',
                hintText: 'e.g. Read 20 pages, 10k steps, Morning Meditation',
                prefixIcon: Icon(Icons.check_circle_rounded),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a habit title' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<HabitFrequency>(
              initialValue: _freq,
              decoration: const InputDecoration(
                labelText: 'Frequency',
                prefixIcon: Icon(Icons.repeat_rounded),
              ),
              items: HabitFrequency.values
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f == HabitFrequency.daily ? 'Every Day (Daily)' : 'Weekly Target'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _freq = v ?? HabitFrequency.daily),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: Text(isEdit ? 'Save Changes' : 'Start Habit Streak'),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
