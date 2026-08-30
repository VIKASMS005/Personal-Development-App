import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../utils/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_card.dart';
import 'forms/journal_form.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  String _searchQuery = '';

  String _moodEmoji(String mood) {
    switch (mood) {
      case 'happy':
        return '😊';
      case 'calm':
        return '😌';
      case 'energetic':
        return '⚡';
      case 'neutral':
        return '😐';
      case 'stressed':
        return '😰';
      case 'sad':
        return '😔';
      default:
        return '✨';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final journalProvider = context.watch<JournalProvider>();

    final entries = journalProvider.entries.where((j) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return j.text.toLowerCase().contains(q) ||
          j.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal & Reflection'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.journal,
        foregroundColor: Colors.white,
        onPressed: () async {
          final j = await JournalForm.show(context);
          if (j != null && auth.uid != null) {
            j.uid = auth.uid!;
            await journalProvider.addJournal(j);
          }
        },
        child: const Icon(Icons.edit_rounded),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search journal entries or tags...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Entries List
          Expanded(
            child: entries.isEmpty
                ? EmptyState(
                    icon: Icons.auto_stories_rounded,
                    title: 'No journal entries',
                    subtitle: 'Capture your thoughts, victories, and reflections',
                    iconColor: AppColors.journal,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final j = entries[index];
                      final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(j.createdAt);
                      final moodEmoji = _moodEmoji(j.mood);

                      return AnimatedListItem(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            accentColor: AppColors.journal,
                            onTap: () async {
                              final edited = await JournalForm.show(context, initial: j);
                              if (edited != null) {
                                await journalProvider.updateJournal(edited);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.journal.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(moodEmoji, style: const TextStyle(fontSize: 14)),
                                          const SizedBox(width: 6),
                                          Text(
                                            dateStr,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.journal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: AppColors.error.withValues(alpha: 0.7),
                                      ),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Delete Entry'),
                                            content: const Text('Delete this journal entry?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await journalProvider.deleteJournal(j.id);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  j.text,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.55,
                                  ),
                                ),
                                if (j.tags.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    children: j.tags.map((tag) {
                                      return Chip(
                                        label: Text(
                                          '#$tag',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: AppColors.journal.withValues(alpha: 0.08),
                                        side: BorderSide.none,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
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
