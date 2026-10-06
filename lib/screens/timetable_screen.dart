import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/timetable_slot.dart';
import '../providers/app_providers.dart';
import '../widgets/ds/ds.dart';
import 'forms/timetable_form.dart';
import 'chatbot_screen.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  String _activeTab = 'Daily';

  static const _days = [
    'Daily',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
    'All',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.uid != null) {
        context.read<TimetableProvider>().loadSlots(auth.uid!);
      }
    });
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'Study':
        return Icons.menu_book_rounded;
      case 'Work':
        return Icons.work_outline_rounded;
      case 'Health':
        return Icons.spa_outlined;
      case 'Workout':
        return Icons.fitness_center_rounded;
      case 'Leisure':
        return Icons.sports_esports_outlined;
      case 'Sleep':
        return Icons.bedtime_outlined;
      default:
        return Icons.event_note_outlined;
    }
  }

  Future<void> _add(AuthProvider auth, TimetableProvider timetable) async {
    final slot = await TimetableFormDialog.show(
      context,
      defaultDay: _activeTab,
    );
    if (slot != null && auth.uid != null) {
      slot.uid = auth.uid!;
      await timetable.addSlot(slot);
    }
  }

  void _openAi() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatbotScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final timetable = context.watch<TimetableProvider>();
    final slots = timetable.getFilteredSlots(_activeTab);
    final done = slots.where((s) => s.isCompleted).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable'),
        actions: [
          IconButton(
            tooltip: 'Plan with AI Coach',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _openAi,
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(auth, timetable),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add block'),
      ),
      body: PageListView(
        children: [
          FilterBar(
            padding: EdgeInsets.zero,
            options: _days.map((d) => FilterOption(d == 'All' ? 'All days' : d)).toList(),
            selectedIndex: _days.indexOf(_activeTab),
            onSelected: (i) => setState(() => _activeTab = _days[i]),
          ),
          const SizedBox(height: AppSpacing.sm),
          InlineBanner(
            tone: StatusTone.info,
            icon: Icons.auto_awesome_outlined,
            message: 'Ask the AI Coach to draft a routine for you.',
            actionLabel: 'Open',
            onAction: _openAi,
          ),
          const SectionGap(),
          if (slots.isEmpty)
            EmptyState(
              icon: Icons.view_timeline_outlined,
              title: _activeTab == 'All' ? 'No routine yet' : _activeTab == 'Daily' ? 'No daily routine yet' : 'Nothing planned for $_activeTab',
              subtitle: 'Add time blocks to shape your day.',
              action: FilledButton(onPressed: () => _add(auth, timetable), child: const Text('Add a block')),
            )
          else ...[
            SectionHeader(
              title: _activeTab == 'All' ? 'All blocks' : _activeTab,
              subtitle: '$done of ${slots.length} done',
            ),
            for (final slot in slots) ...[
              _SlotCard(
                slot: slot,
                icon: _getCategoryIcon(slot.category),
                onToggle: () => timetable.toggleCompleted(slot),
                onEdit: () async {
                  final edited = await TimetableFormDialog.show(context, initial: slot);
                  if (edited != null) {
                    await timetable.updateSlot(edited);
                  }
                },
                onDelete: () async {
                  final confirmed = await ConfirmDialog.show(
                    context,
                    title: 'Delete block?',
                    message: '"${slot.title}" will be removed from your timetable.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (confirmed) {
                    await timetable.deleteSlot(slot.id);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final TimetableSlot slot;
  final IconData icon;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SlotCard({
    required this.slot,
    required this.icon,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.startTime, style: context.text.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                Text(slot.endTime, style: context.text.labelSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
          Container(width: 1, height: 40, margin: const EdgeInsets.only(right: AppSpacing.sm), color: colors.divider),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    decoration: slot.isCompleted ? TextDecoration.lineThrough : null,
                    color: slot.isCompleted ? colors.textSecondary : colors.textPrimary,
                  ),
                ),
                if (slot.description.isNotEmpty)
                  Text(slot.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.xxs + 2),
                Wrap(
                  spacing: AppSpacing.xs - 2,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusBadge(label: slot.category, icon: icon, outlined: true),
                    if (slot.dayOfWeek != 'Daily') StatusBadge(label: slot.dayOfWeek, outlined: true),
                    if (slot.hasReminder) const StatusBadge(label: 'Reminder', icon: Icons.notifications_none_rounded, outlined: true),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: slot.isCompleted ? 'Mark not done' : 'Mark done',
            icon: Icon(
              slot.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: slot.isCompleted ? context.scheme.primary : colors.textSecondary,
            ),
            onPressed: onToggle,
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: colors.error))),
            ],
          ),
        ],
      ),
    );
  }
}
