import 'package:flutter/material.dart';
import '../../models/journal_entry.dart';


class JournalForm extends StatefulWidget {
  final JournalEntry? initial;
  const JournalForm({super.key, this.initial});

  static Future<JournalEntry?> show(BuildContext context, {JournalEntry? initial}) {
    return showDialog<JournalEntry?>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: JournalForm(initial: initial),
      ),
    );
  }

  @override
  State<JournalForm> createState() => _JournalFormState();
}

class _JournalFormState extends State<JournalForm> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _textC;
  late TextEditingController _tagsC;
  String _selectedMood = 'calm';

  static const _moods = [
    ('happy', '😊 Happy', Color(0xFF10B981)),
    ('calm', '😌 Calm', Color(0xFF06B6D4)),
    ('energetic', '⚡ Energetic', Color(0xFFF59E0B)),
    ('neutral', '😐 Neutral', Color(0xFF64748B)),
    ('stressed', '😰 Stressed', Color(0xFFEF4444)),
    ('sad', '😔 Sad', Color(0xFF8B5CF6)),
  ];

  @override
  void initState() {
    super.initState();
    _textC = TextEditingController(text: widget.initial?.text ?? '');
    _tagsC = TextEditingController(text: widget.initial?.tags.join(', ') ?? '');
    _selectedMood = widget.initial?.mood ?? 'calm';
  }

  @override
  void dispose() {
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
                  isEdit ? 'Edit Reflection' : 'Daily Reflection',
                  style: theme.textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('How are you feeling?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _moods.map((m) {
                final isSelected = _selectedMood == m.$1;
                return ChoiceChip(
                  label: Text(m.$2),
                  selected: isSelected,
                  selectedColor: m.$3.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? m.$3 : null,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedMood = m.$1);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _textC,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'What went well today? What did you learn?',
                alignLabelWithHint: true,
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Entry cannot be empty' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _tagsC,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                hintText: 'Gratitude, Growth, Mindset',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded),
                label: Text(isEdit ? 'Save Reflection' : 'Post Entry'),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
