import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../utils/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_card.dart';
import 'forms/habit_form.dart';

/// Case-insensitive match on a habit's title or its frequency
/// (e.g. "daily", "weekly"). Every word typed must appear; an empty query
/// matches everything.
bool matchesHabitSearch(String title, String frequency, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final hay = '${title.toLowerCase()} ${frequency.toLowerCase()}';
  return words.every(hay.contains);
}

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  final _searchC = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }


  List<String> _getLast7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateFormat('yyyy-MM-dd').format(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final habitProvider = context.watch<HabitProvider>();
    final allHabits = habitProvider.habits;
    final habits = _query.trim().isEmpty
        ? allHabits
        : allHabits.where((h) => matchesHabitSearch(h.title, h.frequency.name, _query)).toList();
    final last7Days = _getLast7Days();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits & Streaks'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.habits,
        foregroundColor: Colors.white,
        onPressed: () async {
          final h = await HabitForm.show(context);
          if (h != null && auth.uid != null) {
            h.uid = auth.uid!;
            await habitProvider.addHabit(h);
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: allHabits.isEmpty
              ? EmptyState(
                  icon: Icons.local_fire_department_rounded,
                  title: 'No habits yet',
                  subtitle: 'Start small and build unstoppable daily streaks',
                  iconColor: AppColors.habits,
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _searchC,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search habits...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchC.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) => setState(() => _query = val),
                      ),
                    ),
                    Expanded(
                      child: habits.isEmpty
                          ? EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No matching habits',
                              subtitle: 'No habit matches "${_query.trim()}"',
                              iconColor: AppColors.habits,
                            )
                          : ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: habits.length,
              itemBuilder: (context, index) {
                final h = habits[index];
                final isDoneToday = h.history[todayStr] ?? false;

                return AnimatedListItem(
                  key: ValueKey(h.id),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      accentColor: isDoneToday ? AppColors.success : AppColors.habits,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Daily Checkbox Button
                              GestureDetector(
                                onTap: () {
                                  habitProvider.toggleDay(h, todayStr);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isDoneToday
                                        ? AppColors.success.withValues(alpha: 0.15)
                                        : AppColors.habits.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDoneToday
                                          ? AppColors.success
                                          : AppColors.habits.withValues(alpha: 0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    isDoneToday ? Icons.check_rounded : Icons.circle_outlined,
                                    color: isDoneToday ? AppColors.success : AppColors.habits,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Title & Streak
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      h.title,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.local_fire_department_rounded,
                                          size: 16,
                                          color: h.streak > 0
                                              ? AppColors.accent
                                              : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${h.streak} day streak',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: h.streak > 0
                                                ? AppColors.accent
                                                : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '• ${h.frequency.name.toUpperCase()}',
                                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Edit
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () async {
                                  final edited = await HabitForm.show(context, initial: h);
                                  if (edited != null) {
                                    await habitProvider.updateHabit(edited);
                                  }
                                },
                              ),

                              // Delete
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
                                      title: const Text('Delete Habit'),
                                      content: const Text('Delete this habit permanently?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await habitProvider.deleteHabit(h.id);
                                  }
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // 7-day history dot matrix
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: last7Days.map((dStr) {
                              final isDone = h.history[dStr] ?? false;
                              final dt = DateTime.parse(dStr);
                              final dayName = DateFormat('E').format(dt).substring(0, 2);
                              final isToday = dStr == todayStr;

                              return GestureDetector(
                                onTap: () => habitProvider.toggleDay(h, dStr),
                                child: Column(
                                  children: [
                                    Text(
                                      dayName,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                                        color: isToday ? AppColors.habits : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDone ? AppColors.success : theme.dividerColor.withValues(alpha: 0.3),
                                        border: isToday
                                            ? Border.all(color: AppColors.habits, width: 2)
                                            : null,
                                      ),
                                      child: isDone
                                          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
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
