import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_providers.dart';
import '../utils/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_card.dart';
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
        return Icons.work_rounded;
      case 'Health':
        return Icons.spa_rounded;
      case 'Workout':
        return Icons.fitness_center_rounded;
      case 'Leisure':
        return Icons.sports_esports_rounded;
      case 'Sleep':
        return Icons.bedtime_rounded;
      default:
        return Icons.event_note_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final timetable = context.watch<TimetableProvider>();
    final slots = timetable.getFilteredSlots(_activeTab);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable & Routine'),
        actions: [
          IconButton(
            tooltip: 'Generate with AI',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppColors.chatbotGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatbotScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.timetable,
        foregroundColor: Colors.white,
        tooltip: 'Add Routine Slot',
        child: const Icon(Icons.add_rounded),
        onPressed: () async {
          final slot = await TimetableFormDialog.show(
            context,
            defaultDay: _activeTab,
          );
          if (slot != null && auth.uid != null) {
            slot.uid = auth.uid!;
            await timetable.addSlot(slot);
          }
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
          // 1. Day Selector Tabs
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _days.length,
              itemBuilder: (context, i) {
                final day = _days[i];
                final isSelected = _activeTab == day;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(day),
                    selected: isSelected,
                    selectedColor: AppColors.timetable,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : null,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _activeTab = day);
                    },
                  ),
                );
              },
            ),
          ),

          // 2. AI Assistant Prompt Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatbotScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.secondary.withValues(alpha: 0.12),
                      AppColors.timetable.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.smart_toy_rounded, color: AppColors.secondary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Let AI build your routine',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Text(
                            'Ask GrowBot to create your schedule',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.secondary),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(begin: -0.1),
          ),

          // 3. Timetable Slots List
          Expanded(
            child: slots.isEmpty
                ? EmptyState(
                    icon: Icons.view_timeline_rounded,
                    title: 'No routines for $_activeTab',
                    subtitle: 'Tap + or ask AI to generate your timetable',
                    iconColor: AppColors.timetable,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: slots.length,
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final catColor = Color(slot.colorHex);
                      final icon = _getCategoryIcon(slot.category);

                      return AnimatedListItem(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            accentColor: catColor,
                            child: Row(
                              children: [
                                // Time block
                                Container(
                                  width: 78,
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        slot.startTime,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: catColor,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'to',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        slot.endTime,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: catColor,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Title and category
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(icon, size: 16, color: catColor),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: catColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              slot.category,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: catColor,
                                              ),
                                            ),
                                          ),
                                          if (slot.dayOfWeek != 'Daily') ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '• ${slot.dayOfWeek}',
                                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                                            ),
                                          ],
                                          if (slot.hasReminder) ...[
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.notifications_active_rounded,
                                              size: 13,
                                              color: AppColors.accent.withValues(alpha: 0.8),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        slot.title,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          decoration: slot.isCompleted ? TextDecoration.lineThrough : null,
                                          color: slot.isCompleted
                                              ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                                              : null,
                                        ),
                                      ),
                                      if (slot.description.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          slot.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Checkmark complete
                                IconButton(
                                  icon: Icon(
                                    slot.isCompleted ? Icons.check_circle_rounded : Icons.circle_outlined,
                                    color: slot.isCompleted ? AppColors.success : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                  onPressed: () => timetable.toggleCompleted(slot),
                                ),

                                // Options menu
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                                  onSelected: (action) async {
                                    if (action == 'edit') {
                                      final edited = await TimetableFormDialog.show(
                                        context,
                                        initial: slot,
                                      );
                                      if (edited != null) {
                                        await timetable.updateSlot(edited);
                                      }
                                    } else if (action == 'delete') {
                                      await timetable.deleteSlot(slot.id);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Edit'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                                          SizedBox(width: 8),
                                          Text('Delete', style: TextStyle(color: AppColors.error)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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
