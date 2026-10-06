/// Weeks in this app run inside a calendar month: days 1–7, 8–14, 15–21,
/// 22–28 and 29 to the month's last day. A week never continues into the
/// next month, so the last week of a month can be shorter than 7 days.
class MonthWeek {
  /// First day of the week (midnight).
  final DateTime start;

  /// Day after the week's last day (exclusive end).
  final DateTime end;

  const MonthWeek(this.start, this.end);

  /// Last day of the week (midnight).
  DateTime get last => DateTime(end.year, end.month, end.day - 1);

  /// Number of days in this week (1–7).
  int get length => last.day - start.day + 1;

  /// 1-based week number within its month.
  int get number => (start.day - 1) ~/ 7 + 1;

  List<DateTime> get days =>
      List.generate(length, (i) => DateTime(start.year, start.month, start.day + i));

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) => other is MonthWeek && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The month week containing [date].
MonthWeek monthWeekOf(DateTime date) {
  final startDay = ((date.day - 1) ~/ 7) * 7 + 1;
  final start = DateTime(date.year, date.month, startDay);
  final nextMonth = DateTime(date.year, date.month + 1);
  var end = DateTime(date.year, date.month, startDay + 7);
  if (end.isAfter(nextMonth)) end = nextMonth;
  return MonthWeek(start, end);
}

/// The week before [week] (the last week of the previous month when [week]
/// is the first week of its month).
MonthWeek previousMonthWeek(MonthWeek week) =>
    monthWeekOf(DateTime(week.start.year, week.start.month, week.start.day - 1));

/// The week after [week], or null if it would start after [today].
MonthWeek? nextMonthWeek(MonthWeek week, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  if (week.end.isAfter(t)) return null;
  return monthWeekOf(week.end);
}
