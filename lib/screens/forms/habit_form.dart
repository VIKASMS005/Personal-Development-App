import 'package:flutter/material.dart';
import '../../models/habit.dart';
import '../../widgets/ds/ds.dart';

class HabitForm extends StatefulWidget {
  final Habit? initial;
  const HabitForm({super.key, this.initial});

  static Future<Habit?> show(BuildContext context, {Habit? initial}) => showModalBottomSheet<Habit?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => HabitForm(initial: initial),
      );

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
      uid: widget.initial?.uid ?? 'local_user',
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

    return SheetScaffold(
      title: isEdit ? 'Edit habit' : 'New habit',
      footer: FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
        child: Text(isEdit ? 'Save changes' : 'Add habit'),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleC,
              autofocus: !isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Habit',
                hintText: 'e.g. Read 20 pages',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a habit' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('How often'),
            AppSegmented<HabitFrequency>(
              segments: {
                for (final f in HabitFrequency.values) f: f == HabitFrequency.daily ? 'Every day' : 'Weekly',
              },
              icons: {
                for (final f in HabitFrequency.values) f: f == HabitFrequency.daily ? Icons.today_outlined : Icons.date_range_outlined,
              },
              selected: _freq,
              onChanged: (v) => setState(() => _freq = v),
            ),
          ],
        ),
      ),
    );
  }
}
