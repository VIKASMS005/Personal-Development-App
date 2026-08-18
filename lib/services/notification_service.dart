import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'grow_reminders_channel_v10';
  static const String _channelName = 'Grow Reminders & Tasks';
  static const String _channelDesc =
      'High-priority notifications for reminders, task alerts, and habit tracking';

  static const String _alarmChannelId = 'grow_alarm_loud_channel_v10';
  static const String _alarmChannelName = 'Grow Loud Alarms';
  static const String _alarmChannelDesc =
      'High-priority alarm stream notifications that ring aloud with vibration';

  static Timer? _ringtoneAutoOffTimer;

  static Future<void> init() async {
    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification clicked: ${details.payload}');
        stopRingtone();
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

      // 2. Dedicated Alarm channel
      final alarmChannel = AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: _alarmChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        showBadge: true,
      );
      await androidPlugin.createNotificationChannel(alarmChannel);
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
      // Respects device alarm volume slider without hardcoded force
      await FlutterRingtonePlayer().playAlarm(
        looping: true,
        asAlarm: true,
      );
    } catch (e) {
      debugPrint('Error playing alarm ringtone: $e');
    }
  }

  /// Plays a 7-second ringtone for Timer completion that respects device volume
  static Future<void> playTimerRingtone() async {
    try {
      _ringtoneAutoOffTimer?.cancel();
      // asAlarm: false ensures it respects the user's current notification/media volume
      await FlutterRingtonePlayer().playNotification(
        looping: true,
        asAlarm: false,
      );
      _ringtoneAutoOffTimer = Timer(const Duration(seconds: 7), () {
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
      // asAlarm: false ensures it respects the user's current notification/media volume
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
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
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
        );
      }
    }
  }

  /// Schedules an alarm with native alarmClock trigger and auto-off missed alarm notification
  static Future<void> scheduleAlarm({
    required int id,
    required String title,
    required DateTime dateTime,
    String body = 'Time to wake up and start your routine!',
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
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

    // 1. Initial Alarm Trigger
    final t1 = tz.TZDateTime.now(tz.local).add(duration);
    await _scheduleZoned(
      id: id,
      title: '⏰ $title',
      body: body,
      scheduledDate: t1,
      details: androidDetails,
      isAlarm: true,
    );

    // 2. Repeat 1 (3 minutes later)
    final t2 = t1.add(const Duration(minutes: 3));
    await _scheduleZoned(
      id: id + 100000,
      title: '⏰ (Repeat 1/3) $title',
      body: 'Alarm repeat 1 of 3: $body',
      scheduledDate: t2,
      details: androidDetails,
      isAlarm: true,
    );

    // 3. Repeat 2 (6 minutes later)
    final t3 = t1.add(const Duration(minutes: 6));
    await _scheduleZoned(
      id: id + 200000,
      title: '⏰ (Repeat 2/3) $title',
      body: 'Alarm repeat 2 of 3: $body',
      scheduledDate: t3,
      details: androidDetails,
      isAlarm: true,
    );

    // 4. Auto-off & Missed Alarm Notification (9 minutes later if user didn't turn off manually)
    final t4 = t1.add(const Duration(minutes: 9));
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
      id: id + 300000,
      title: '⏰ Missed Alarm: $title',
      body: 'Alarm rang 3 times and was automatically turned off.',
      scheduledDate: t4,
      details: missedDetails,
      isAlarm: false,
    );
  }

  static Future<void> cancelAlarm(int id) async {
    await _plugin.cancel(id);
    await _plugin.cancel(id + 100000);
    await _plugin.cancel(id + 200000);
    await _plugin.cancel(id + 300000);
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required DateTime dateTime,
    String body = 'Scheduled reminder alert',
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
    );
  }

  static Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
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
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
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
  static Future<void> scheduleHabitStreakWarning({
    required int id,
    required String habitTitle,
  }) async {
    await scheduleDailyReminder(
      id: id,
      title: '🔥 Streak Alert: $habitTitle',
      body: "Don't break the chain! You haven't completed $habitTitle today. Keep your momentum going!",
      hour: 20,
      minute: 30,
    );
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
    final random = Random();
    final quote = _dailyQuotes[random.nextInt(_dailyQuotes.length)];
    await scheduleDailyReminder(
      id: 9999,
      title: quote.$1,
      body: quote.$2,
      hour: 9,
      minute: 0,
    );
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
