import 'package:flutter/material.dart';
import '../../models/journal_entry.dart';
import '../../widgets/ds/ds.dart';


class JournalForm extends StatefulWidget {
  final JournalEntry? initial;
  const JournalForm({super.key, this.initial});

  static Future<JournalEntry?> show(BuildContext context, {JournalEntry? initial}) => showModalBottomSheet<JournalEntry?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => JournalForm(initial: initial),
      );

  @override
  State<JournalForm> createState() => _JournalFormState();
}

class _JournalFormState extends State<JournalForm> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _titleC;
  late TextEditingController _textC;
  late TextEditingController _tagsC;
  String _selectedMood = 'calm';

  @override
  void initState() {
    super.initState();
    _titleC = TextEditingController(text: widget.initial?.title ?? '');
    _textC = TextEditingController(text: widget.initial?.text ?? '');
    _tagsC = TextEditingController(text: widget.initial?.tags.join(', ') ?? '');
    _selectedMood = widget.initial?.mood ?? 'calm';
  }

  @override
  void dispose() {
    _titleC.dispose();
    _textC.dispose();
    _tagsC.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;

    final tags = _tagsC.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final entry = JournalEntry(
      id: widget.initial?.id,
      uid: widget.initial?.uid ?? 'local_user',
      title: _titleC.text.trim(),
      text: _textC.text.trim(),
      mood: _selectedMood,
      tags: tags,
      createdAt: widget.initial?.createdAt,
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final moods = journalMoods.contains(_selectedMood) ? journalMoods : [...journalMoods, _selectedMood];

    return SheetScaffold(
      title: isEdit ? 'Edit entry' : 'New journal entry',
      footer: FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
        child: Text(isEdit ? 'Save changes' : 'Save entry'),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FieldLabel('How are you feeling?'),
            ChoiceWrap<String>(
              options: moods,
              selected: _selectedMood,
              labelOf: moodLabel,
              iconOf: moodIcon,
              onSelected: (m) => setState(() => _selectedMood = m),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _titleC,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Evening reflection',
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _textC,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Entry',
                hintText: 'What went well today? What did you learn?',
                alignLabelWithHint: true,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please write something' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _tagsC,
              decoration: const InputDecoration(
                labelText: 'Tags (optional)',
                hintText: 'Gratitude, Growth',
                helperText: 'Separate tags with commas',
                prefixIcon: Icon(Icons.tag_rounded, size: AppSizes.iconMd),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
