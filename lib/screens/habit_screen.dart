import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/habit.dart';
import '../providers/app_providers.dart';
import '../widgets/ds/ds.dart';
import 'forms/habit_form.dart';

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  List<String> _getLast7Days() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateFormat('yyyy-MM-dd').format(d);
    });
  }

  Future<void> _add(BuildContext context, AuthProvider auth, HabitProvider habitProvider) async {
    final h = await HabitForm.show(context);
    if (h != null && auth.uid != null) {
      h.uid = auth.uid!;
      await habitProvider.addHabit(h);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final habitProvider = context.watch<HabitProvider>();
    final habits = habitProvider.habits;
    final last7Days = _getLast7Days();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final doneToday = habits.where((h) => h.history[todayStr] ?? false).length;
    final bestStreak = habits.fold<int>(0, (m, h) => h.streak > m ? h.streak : m);

    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, auth, habitProvider),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add habit'),
      ),
      body: habits.isEmpty
          ? EmptyState(
              icon: Icons.local_fire_department_outlined,
              title: 'No habits yet',
              subtitle: 'Start with one small daily action and build a streak.',
              action: FilledButton(onPressed: () => _add(context, auth, habitProvider), child: const Text('Add a habit')),
            )
          : PageListView(
              children: [
                StatRow(children: [
                  StatCard(
                    label: 'Done today',
                    value: '$doneToday',
                    unit: '/ ${habits.length}',
                    icon: Icons.check_circle_outline_rounded,
                    tone: doneToday == habits.length ? StatusTone.success : StatusTone.primary,
                  ),
                  StatCard(
                    label: 'Best streak',
                    value: '$bestStreak',
                    unit: bestStreak == 1 ? 'day' : 'days',
                    icon: Icons.local_fire_department_outlined,
                    tone: StatusTone.warning,
                  ),
                ]),
                const SectionGap(),
                const SectionHeader(title: 'Your habits', subtitle: 'Tap a day to mark it done or undo it.'),
                for (final h in habits) ...[
                  _HabitCard(
                    habit: h,
                    days: last7Days,
                    todayStr: todayStr,
                    onToggle: (d) => habitProvider.toggleDay(h, d),
                    onEdit: () async {
                      final edited = await HabitForm.show(context, initial: h);
                      if (edited != null) {
                        await habitProvider.updateHabit(edited);
                      }
                    },
                    onDelete: () async {
                      final ok = await ConfirmDialog.show(
                        context,
                        title: 'Delete habit?',
                        message: '"${h.title}" and its history will be removed.',
                        confirmLabel: 'Delete',
                        destructive: true,
                      );
                      if (ok) {
                        await habitProvider.deleteHabit(h.id);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  final Habit habit;
  final List<String> days;
  final String todayStr;
  final ValueChanged<String> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HabitCard({
    required this.habit,
    required this.days,
    required this.todayStr,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final h = habit;
    final colors = context.colors;
    final isDoneToday = h.history[todayStr] ?? false;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.title, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: AppSpacing.xs - 2,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        StatusBadge(
                          label: '${h.streak} day streak',
                          icon: Icons.local_fire_department_outlined,
                          tone: h.streak > 0 ? StatusTone.warning : StatusTone.neutral,
                        ),
                        StatusBadge(label: h.frequency == HabitFrequency.daily ? 'Daily' : 'Weekly', outlined: true),
                      ],
                    ),
                  ],
                ),
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
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: days.map((dStr) {
                final isDone = h.history[dStr] ?? false;
                final dt = DateTime.parse(dStr);
                final isToday = dStr == todayStr;
                return Expanded(
                  child: Semantics(
                    button: true,
                    checked: isDone,
                    label: '${DateFormat('EEEE').format(dt)}${isToday ? ', today' : ''}',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onToggle(dStr),
                      borderRadius: AppRadius.smAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                        child: Column(
                          children: [
                            Text(
                              DateFormat('E').format(dt).substring(0, 1),
                              style: context.text.labelSmall?.copyWith(
                                color: isToday ? colors.textPrimary : colors.textSecondary,
                                fontWeight: isToday ? FontWeight.w700 : null,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            AnimatedContainer(
                              duration: AppMotion.fast,
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDone ? context.scheme.primary : colors.surfaceMuted,
                                border: Border.all(
                                  color: isToday ? context.scheme.primary : (isDone ? context.scheme.primary : colors.border),
                                  width: isToday ? 2 : 1,
                                ),
                              ),
                              child: isDone ? Icon(Icons.check_rounded, size: AppSizes.iconSm, color: context.scheme.onPrimary) : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (!isDoneToday) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OutlinedButton.icon(
                onPressed: () => onToggle(todayStr),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                icon: const Icon(Icons.check_rounded, size: AppSizes.iconMd),
                label: const Text('Mark today done'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
