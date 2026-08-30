import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/calendar_event.dart';
import '../utils/app_colors.dart';
import '../utils/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final calProvider = context.watch<CalendarProvider>();
    final dayEvents = calProvider.getEventsForDay(_selectedDay);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar & Events')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.calendar,
        foregroundColor: Colors.white,
        onPressed: () => _addEvent(auth.uid),
        child: const Icon(Icons.add_rounded),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Card(
              child: TableCalendar<CalendarEvent>(
                firstDay: DateTime.utc(2020),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _format,
                onFormatChanged: (f) => setState(() => _format = f),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) => _focusedDay = focused,
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: AppColors.calendar.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: AppColors.calendar,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  markersMaxCount: 1,
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: true,
                  titleCentered: true,
                  formatButtonDecoration: BoxDecoration(
                    color: AppColors.calendar.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  formatButtonTextStyle: const TextStyle(
                    color: AppColors.calendar,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                eventLoader: calProvider.getEventsForDay,
              ),
            ).animate().fadeIn().slideY(begin: 0.05),

            const SizedBox(height: 20),

            Text(
              'Events on ${DateFormat('MMMM dd, yyyy').format(_selectedDay)}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ).animate().fadeIn(delay: 80.ms),

            const SizedBox(height: 12),

            if (dayEvents.isEmpty)
              EmptyState(
                icon: Icons.event_rounded,
                title: 'No events scheduled',
                subtitle: 'Tap + to schedule an event or milestone',
                iconColor: AppColors.calendar,
              )
            else
              ...dayEvents.asMap().entries.map((entry) {
                final e = entry.value;
                final diff = e.dateTime.difference(DateTime.now());
                final timeStr = DateFormat('hh:mm a').format(e.dateTime);

                return AnimatedListItem(
                  index: entry.key,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      accentColor: AppColors.calendar,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.calendar.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.event_rounded,
                              color: AppColors.calendar,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.title,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(timeStr, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: diff.isNegative
                                  ? AppColors.error.withValues(alpha: 0.12)
                                  : AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              diff.isNegative ? 'Passed' : _formatDuration(diff),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: diff.isNegative ? AppColors.error : AppColors.success,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.error.withValues(alpha: 0.7),
                            ),
                            onPressed: () => calProvider.deleteEvent(e.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    ),
  ),
);
  }

  Future<void> _addEvent(String? uid) async {
    if (uid == null) return;
    final titleCtrl = TextEditingController();
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: DateTime(now.year + 5),
      initialDate: _selectedDay,
    );
    if (picked == null || !mounted) return;

    final time = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.now(),
      helpText: 'Event Time (AM / PM)',
    );
    if (time == null || !mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Event Title'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(hintText: 'e.g. Project Review, Exam'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, titleCtrl.text.trim()),
            child: const Text('Add Event'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final dt = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time.hour,
      time.minute,
    );

    final event = CalendarEvent(
      uid: uid,
      title: name,
      dateTime: dt,
    );

    await context.read<CalendarProvider>().addEvent(event);
    if (!mounted) return;
    setState(() {
      _selectedDay = picked;
      _focusedDay = picked;
    });
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m left';
  }
}
