import 'package:flutter/material.dart';

class AppTimePicker {
  /// Displays a time picker explicitly configured with 12-Hour format and AM/PM toggles
  static Future<TimeOfDay?> show(
    BuildContext context, {
    TimeOfDay? initialTime,
    String? helpText,
  }) async {
    return showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      helpText: helpText ?? 'Select Time (AM / PM)',
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  /// Formats a TimeOfDay into an unambiguous 12-hour String with AM/PM (e.g. 08:30 AM)
  static String format(BuildContext context, TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  /// Formats DateTime into an unambiguous 12-hour String with AM/PM
  static String formatDateTime(DateTime dt) {
    final hourOfPeriod = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${hourOfPeriod.toString().padLeft(2, '0')}:$minute $period';
  }
}
