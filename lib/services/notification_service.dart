import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../utils/month_weeks.dart';

class NotificationService {
  /// Deterministic FNV-1a 32-bit hash for a [String] id.
  /// Unlike Dart's [String.hashCode], this is stable across app restarts,
  /// so notification cancel/update calls always target the correct OS alarm.
  static int stableId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    // Ensure positive and within Android's 32-bit signed int range
    return hash & 0x7FFFFFFF;
  }

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'grow_reminders_channel_v10';
  static const String _channelName = 'Grow Reminders & Tasks';
  static const String _channelDesc =
      'High-priority notifications for reminders, task alerts, and habit tracking';

  static const String _alarmChannelId = 'grow_alarm_loud_channel_v12';
  static const String _alarmChannelName = 'Grow Loud Alarms';
  static const String _alarmChannelDesc =
      'High-priority alarm stream notifications that ring aloud with vibration';

  static const String _timerChannelId = 'grow_timer_loud_channel_v12';
  static const String _timerChannelName = 'Grow Focus Timers';
  static const String _timerChannelDesc =
      'Loud timer completion alerts playing on the alarm audio stream';

  static Timer? _ringtoneAutoOffTimer;

  /// Callback invoked when a reminder notification is tapped.
  /// Set this from the app once ReminderProvider is available.
  static void Function(String reminderId)? onReminderTapped;

  /// Callback invoked when an alarm notification is tapped or triggered.
  /// Passes (alarmId, label, snoozeCount).
  static void Function(String alarmId, String label, int snoozeCount)? onAlarmTriggered;

  static Future<void> init() async {
    tz.initializeTimeZones();
    try {
      const channel = MethodChannel('com.grow.app/settings');
      final String? timeZoneName = await channel.invokeMethod<String>('getDeviceTimeZone');
      if (timeZoneName != null && timeZoneName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint('[NotificationService] Local timezone configured: $timeZoneName');
      }
    } catch (e) {
      debugPrint('[NotificationService] Could not set native timezone location: $e');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: payload=${details.payload}');
        final payload = details.payload ?? '';
        if (payload.startsWith('reminder:')) {
          stopRingtone();
          final reminderId = payload.substring('reminder:'.length);
          onReminderTapped?.call(reminderId);
        } else if (payload.startsWith('alarm:')) {
          // Format: 'alarm:$alarmId:$title:$snoozeCount'
          final parts = payload.split(':');
          if (parts.length >= 4) {
            final alarmId = parts[1];
            final title = parts[2];
            final snoozeCount = int.tryParse(parts[3]) ?? 0;
            onAlarmTriggered?.call(alarmId, title, snoozeCount);
          }
        }
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      // 1. Reminders channel (respects system volume with pleasant vibration)
      final remindersChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(remindersChannel);

      // 2. Dedicated Alarm channel with bundled raw alarm audio
      final alarmChannel = AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: _alarmChannelDesc,
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_ringtone'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(alarmChannel);

      // 3. Dedicated Timer channel with bundled raw timer audio
      final timerChannel = AndroidNotificationChannel(
        _timerChannelId,
        _timerChannelName,
        description: _timerChannelDesc,
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('timer_ringtone'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(timerChannel);
    }

    await requestPermissions();
  }

  static Future<void> requestPermissions() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }
  }

  // ==================== RINGTONE AUDIO PLAYERS (VOLUME-AWARE) ====================
  static Future<void> playAlarmRingtone() async {
    try {
      _ringtoneAutoOffTimer?.cancel();
      // Loud looping alarm sound using Android's alarm audio stream
      await FlutterRingtonePlayer().playAlarm(
        looping: true,
        asAlarm: true,
      );
      // Auto-silence alarm after 3 minutes if unattended
      _ringtoneAutoOffTimer = Timer(const Duration(minutes: 3), () {
        stopRingtone();
      });
    } catch (e) {
      debugPrint('Error playing alarm ringtone: $e');
    }
  }

  /// Plays a loud, looping alarm ringtone when a focus timer finishes
  static Future<void> playTimerRingtone() async {
    try {
      _ringtoneAutoOffTimer?.cancel();
      // Uses the alarm audio stream so it rings aloud even in silent/vibrate mode
      await FlutterRingtonePlayer().playAlarm(
        looping: true,
        asAlarm: true,
      );
      // Auto-silence timer ringtone after 30 seconds if unattended
      _ringtoneAutoOffTimer = Timer(const Duration(seconds: 30), () {
        stopRingtone();
      });
    } catch (e) {
      debugPrint('Error playing timer ringtone: $e');
    }
  }

  /// Plays a 7-second ringtone for reminders that respects device volume
  static Future<void> playReminderRingtone() async {
    try {
      _ringtoneAutoOffTimer?.cancel();
      await FlutterRingtonePlayer().playNotification(
        looping: true,
        asAlarm: false,
      );
      _ringtoneAutoOffTimer = Timer(const Duration(seconds: 7), () {
        stopRingtone();
      });
    } catch (e) {
      debugPrint('Error playing reminder ringtone: $e');
    }
  }

  static Future<void> stopRingtone() async {
    try {
      _ringtoneAutoOffTimer?.cancel();
      await FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('Error stopping ringtone: $e');
    }
  }

  // ==================== NOTIFICATIONS ====================
  static Future<void> showSimple({
    required int id,
    required String title,
    required String body,
    String? channelId,
    String? channelName,
    AndroidNotificationSound? sound,
    bool isTimer = false,
  }) async {
    final targetChannelId = channelId ?? (isTimer ? _timerChannelId : _channelId);
    final targetChannelName = channelName ?? (isTimer ? _timerChannelName : _channelName);
    final targetSound = sound ?? (isTimer ? const RawResourceAndroidNotificationSound('timer_ringtone') : null);

    final androidDetails = AndroidNotificationDetails(
      targetChannelId,
      targetChannelName,
      channelDescription: isTimer ? _timerChannelDesc : _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      audioAttributesUsage: isTimer ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      sound: targetSound,
      playSound: true,
      enableVibration: true,
      vibrationPattern: isTimer
          ? Int64List.fromList([0, 1000, 500, 1000, 500, 1000])
          : Int64List.fromList([0, 800, 300, 800, 300, 800]),
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  static Future<void> _scheduleZoned({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required AndroidNotificationDetails details,
    bool isAlarm = false,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        NotificationDetails(
          android: details,
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        androidScheduleMode: isAlarm
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (e) {
      debugPrint('Error scheduling exact notification (fallback to exactAllowWhileIdle): $e');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          NotificationDetails(android: details),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          matchDateTimeComponents: matchDateTimeComponents,
        );
      } catch (e2) {
        debugPrint('Fallback to inexact: $e2');
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          NotificationDetails(android: details),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
          matchDateTimeComponents: matchDateTimeComponents,
        );
      }
    }
  }

  /// Schedules an alarm with native alarmClock trigger, 3-snooze cycle, and auto-off missed alarm notification
  static Future<void> scheduleAlarm({
    required int id,
    required String title,
    required DateTime dateTime,
    String body = 'Time to wake up and start your routine!',
    DateTimeComponents? matchDateTimeComponents,
    int initialSnoozeCount = 0,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: const RawResourceAndroidNotificationSound('alarm_ringtone'),
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    final duration = dateTime.difference(DateTime.now());
    if (duration.isNegative) {
      return;
    }

    final t1 = tz.TZDateTime.now(tz.local).add(duration);

    // 1. Initial Alarm Trigger (or current snooze)
    await _scheduleZoned(
      id: id,
      title: '⏰ $title',
      body: body,
      scheduledDate: t1,
      details: androidDetails,
      isAlarm: true,
      payload: 'alarm:$id:$title:$initialSnoozeCount',
      matchDateTimeComponents: matchDateTimeComponents,
    );

    // If starting from 0, schedule the 3 automatic snoozes (+5m, +10m, +15m) and missed alarm (+20m)
    if (initialSnoozeCount == 0) {
      // 2. Snooze 1 of 3 (5 minutes later)
      final t2 = t1.add(const Duration(minutes: 5));
      await _scheduleZoned(
        id: id + 100000,
        title: '⏰ (Snooze 1/3) $title',
        body: 'Alarm snooze 1 of 3: $body',
        scheduledDate: t2,
        details: androidDetails,
        isAlarm: true,
        payload: 'alarm:$id:$title:1',
      );

      // 3. Snooze 2 of 3 (10 minutes later)
      final t3 = t1.add(const Duration(minutes: 10));
      await _scheduleZoned(
        id: id + 200000,
        title: '⏰ (Snooze 2/3) $title',
        body: 'Alarm snooze 2 of 3: $body',
        scheduledDate: t3,
        details: androidDetails,
        isAlarm: true,
        payload: 'alarm:$id:$title:2',
      );

      // 4. Snooze 3 of 3 (15 minutes later - Final Snooze)
      final t4 = t1.add(const Duration(minutes: 15));
      await _scheduleZoned(
        id: id + 300000,
        title: '⏰ (Snooze 3/3 - Final) $title',
        body: 'Final alarm! No more snoozes remaining.',
        scheduledDate: t4,
        details: androidDetails,
        isAlarm: true,
        payload: 'alarm:$id:$title:3',
      );

      // 5. Auto-off & Missed Alarm Notification (20 minutes later if user never turned it off)
      final t5 = t1.add(const Duration(minutes: 20));
      final missedDetails = AndroidNotificationDetails(
        _alarmChannelId,
        _alarmChannelName,
        channelDescription: _alarmChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      );
      await _scheduleZoned(
        id: id + 400000,
        title: '⏰ Missed Alarm: $title',
        body: 'Alarm rang 3 times and was automatically turned off.',
        scheduledDate: t5,
        details: missedDetails,
        isAlarm: false,
      );
    }
  }

  static Future<void> cancelAlarm(int id) async {
    await _plugin.cancel(id);
    await _plugin.cancel(id + 100000);
    await _plugin.cancel(id + 200000);
    await _plugin.cancel(id + 300000);
    await _plugin.cancel(id + 400000);
  }

  static Future<void> sendMissedAlarmNotification({
    required int id,
    required String title,
    required String timeStr,
  }) async {
    final missedDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );
    await _plugin.show(
      id + 400000,
      '⏰ Missed Alarm: $title',
      'Alarm for $timeStr was missed after 3 snoozes.',
      NotificationDetails(android: missedDetails),
    );
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime dateTime,
    String body = 'Scheduled reminder alert',
    String? reminderId, // optional: used to auto-complete reminder on tap
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );

    final duration = dateTime.difference(DateTime.now());
    if (duration.isNegative) {
      return;
    }
    final scheduledDate = tz.TZDateTime.now(tz.local).add(duration);

    await _scheduleZoned(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      details: androidDetails,
      isAlarm: false,
      payload: reminderId != null ? 'reminder:$reminderId' : null,
    );
  }

  static Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    bool skipToday = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (skipToday || target.isBefore(now)) {
      target = DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
    final duration = target.difference(now);
    final scheduledDate = tz.TZDateTime.now(tz.local).add(duration);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ==================== HABIT STREAK WARNING ====================
  /// Daily 8:30 PM warning. When the habit is already done today the first
  /// warning is tomorrow's, so the "you haven't completed it today" text is
  /// never sent on a day it was completed.
  ///
  /// A [weekly] habit instead gets one warning at 8:30 PM on the last day of
  /// the week (1–7, 8–14, ...): this week's if it isn't done yet ([doneToday]
  /// then means "done this week"), otherwise next week's. It is re-armed each
  /// time habits load.
  static Future<void> scheduleHabitStreakWarning({
    required int id,
    required String habitTitle,
    bool doneToday = false,
    bool weekly = false,
  }) async {
    if (weekly) {
      await _plugin.cancel(id);
      final now = DateTime.now();
      var week = monthWeekOf(now);
      var target = DateTime(week.last.year, week.last.month, week.last.day, 20, 30);
      if (doneToday || target.isBefore(now)) {
        week = monthWeekOf(week.end);
        target = DateTime(week.last.year, week.last.month, week.last.day, 20, 30);
      }
      await _plugin.zonedSchedule(
        id,
        '🔥 Streak Alert: $habitTitle',
        "Last day of the week! You haven't completed $habitTitle this week yet.",
        tz.TZDateTime.now(tz.local).add(target.difference(now)),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return;
    }
    await scheduleDailyReminder(
      id: id,
      title: '🔥 Streak Alert: $habitTitle',
      body: "Don't break the chain! You haven't completed $habitTitle today. Keep your momentum going!",
      hour: 20,
      minute: 30,
      skipToday: doneToday,
    );
  }

  // ==================== DAILY DIGEST (8:50 AM) ====================
  /// Schedules a daily notification at 8:50 AM.
  /// Delivers yesterday's step summary and screen time overview. Its sound is
  /// the notification's own, so it plays even when the app is closed.
  static Future<void> scheduleDailyDigest() async {
    const int digestId = 88500; // unique id for 08:50 digest

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Daily morning analytics digest at 8:50 AM',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
    );

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, 8, 50);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    final duration = target.difference(now);
    final scheduledDate = tz.TZDateTime.now(tz.local).add(duration);

    try {
      await _plugin.zonedSchedule(
        digestId,
        '🌅 Good Morning! Your Daily Digest',
        '💪 Check your steps, screen time & task progress for the day ahead!',
        scheduledDate,
        NotificationDetails(
          android: androidDetails,
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeats daily
      );
      // (An extra in-app ringtone used to be timed here. It only played if the
      // app happened to be running at 8:50 and repeated once per app start,
      // so the notification's own sound is used instead.)
    } catch (e) {
      debugPrint('Error scheduling daily digest: $e');
    }
  }

  // ==================== DAILY RANDOM INSPIRATION ====================
  static const List<(String, String)> _dailyQuotes = [
    ('🌱 Focus on Small Wins', 'Success is the sum of small efforts repeated day in and day out.'),
    ('⚡ Master Your Routine', 'First we make our habits, then our habits make us.'),
    ('🎯 Prioritize Deep Work', 'Do what is hard now and life will be easy later.'),
    ('💎 Keep Your Momentum', 'You don’t have to be extreme, just consistent.'),
    ('🧠 Clear Your Mind', 'Reflect in your journal today to reduce stress and gain clarity.'),
    ('💰 Mindful Spending', 'Track your expenses today to stay on top of your financial freedom.'),
    ('🔥 Protect Your Streaks', 'Never break a habit twice. If you slip once, bounce back immediately.'),
  ];

  static Future<void> scheduleDailyInspiration() async {
    // BUG 9 FIX: Cancel the old recurring single-quote notification, then schedule
    // 7 individual one-shot notifications (one per day for the next 7 days),
    // each using a different quote. This way users see a fresh quote every day.
    await _plugin.cancel(9999); // cancel old recurring

    final now = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final day = now.add(Duration(days: i));
      final quoteIndex = (day.difference(DateTime(day.year, 1, 1)).inDays) % _dailyQuotes.length;
      final quote = _dailyQuotes[quoteIndex];

      // Deliver at 9:00 AM of that day; skip today if 9 AM already passed
      var deliveryTime = DateTime(day.year, day.month, day.day, 9, 0, 0);
      if (deliveryTime.isBefore(now)) continue;

      final tzDelivery = tz.TZDateTime.from(deliveryTime, tz.local);
      const androidDetails = AndroidNotificationDetails(
        'daily_inspiration',
        'Daily Inspiration',
        channelDescription: 'Daily motivational quote',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        playSound: false,
        enableVibration: false,
        styleInformation: BigTextStyleInformation(''),
      );

      // Use ID 9990..9996 for days 0-6 so they don't collide with each other
      await _plugin.zonedSchedule(
        9990 + i,
        quote.$1,
        quote.$2,
        tzDelivery,
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: false),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
