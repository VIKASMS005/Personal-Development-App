import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/journal_entry.dart';
import '../providers/app_providers.dart';
import '../widgets/ds/ds.dart';
import 'forms/journal_form.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  String _searchQuery = '';
  final _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _add(AuthProvider auth, JournalProvider journalProvider) async {
    final j = await JournalForm.show(context);
    if (j != null) {
      j.uid = auth.uid ?? 'local_user';
      await journalProvider.addJournal(j);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final journalProvider = context.watch<JournalProvider>();

    final entries = journalProvider.entries.where((j) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return j.title.toLowerCase().contains(q) ||
          j.text.toLowerCase().contains(q) ||
          j.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    // Group by day for readable scanning.
    final groups = <String, List<JournalEntry>>{};
    final now = DateTime.now();
    for (final j in entries) {
      final d = j.createdAt;
      final label = DateUtils.isSameDay(d, now)
          ? 'Today'
          : DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))
              ? 'Yesterday'
              : DateFormat(d.year == now.year ? 'EEEE, MMM d' : 'MMM d, yyyy').format(d);
      groups.putIfAbsent(label, () => []).add(j);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(auth, journalProvider),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New entry'),
      ),
      body: PageListView(
        children: [
          TextField(
            controller: _searchC,
            decoration: InputDecoration(
              hintText: 'Search entries or tags',
              prefixIcon: const Icon(Icons.search_rounded, size: AppSizes.iconMd),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: AppSizes.iconMd),
                      onPressed: () => setState(() {
                        _searchC.clear();
                        _searchQuery = '';
                      }),
                    )
                  : null,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: AppSpacing.md),
          if (entries.isEmpty)
            EmptyState(
              icon: _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.auto_stories_outlined,
              title: _searchQuery.isNotEmpty ? 'No matching entries' : 'No entries yet',
              subtitle: _searchQuery.isNotEmpty
                  ? 'Try a different word or tag.'
                  : 'Capture your thoughts, lessons and wins each day.',
              action: _searchQuery.isEmpty
                  ? FilledButton(onPressed: () => _add(auth, journalProvider), child: const Text('Write an entry'))
                  : null,
            )
          else
            for (final g in groups.entries) ...[
              SectionHeader(title: g.key),
              for (final j in g.value) ...[
                _JournalCard(
                  entry: j,
                  onTap: () async {
                    final edited = await JournalForm.show(context, initial: j);
                    if (edited != null) {
                      await journalProvider.updateJournal(edited);
                    }
                  },
                  onDelete: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: 'Delete entry?',
                      message: 'This journal entry will be removed permanently.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    );
                    if (ok) {
                      await journalProvider.deleteJournal(j.id);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _JournalCard({required this.entry, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final j = entry;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: moodLabel(j.mood), icon: moodIcon(j.mood), tone: StatusTone.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(DateFormat('h:mm a').format(j.createdAt), style: context.text.labelSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Delete entry',
                icon: Icon(Icons.delete_outline_rounded, size: AppSizes.iconMd, color: context.colors.textSecondary),
                onPressed: onDelete,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (j.title.isNotEmpty) ...[
                  Text(j.title, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(
                  j.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(height: 1.5, color: context.colors.textSecondary),
                ),
                if (j.tags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs - 2,
                    runSpacing: AppSpacing.xxs,
                    children: j.tags.map((tag) => StatusBadge(label: '#$tag', outlined: true)).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
