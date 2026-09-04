import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_record.dart';
import 'database_service.dart';

/// StepTrackerService — drives hardware step tracking silently with ZERO notifications.
///
/// Hardware Architecture:
///   1. The Android device's dedicated Sensor Hub tracks hardware TYPE_STEP_COUNTER
///      in low-power silicon continuously from boot (including when phone is locked/asleep/in pocket).
///   2. MainActivity registers the sensor listener silently (no foreground notification).
///   3. On app start, resume, or periodic refresh, StepTrackerService reads the hardware count
///      and calculates `todaySteps = (rawSteps - baselineForToday) + preRebootSteps`.
///   4. Device reboots reset rawSteps to 0, which is handled gracefully without losing previous steps.
///   5. Saves to SQLite and SharedPreferences atomically.
class StepTrackerService {
  static final StepTrackerService instance = StepTrackerService._internal();
  StepTrackerService._internal();

  static const _channel = MethodChannel('com.grow.app/settings');
  final DatabaseService _db = DatabaseService.instance;

  int _todaySteps = 0;
  bool _isAvailable = true;
  bool _hasHardwareSensor = true;
  String? _currentUid;
  String? _lastKnownDate;

  // Polling timer — refreshes hardware count every 15 seconds while app is active
  Timer? _pollTimer;

  int get todaySteps => _todaySteps;
  bool get isAvailable => _isAvailable;
  bool get hasHardwareSensor => _hasHardwareSensor;

  Function(int steps)? onStepUpdate;
  Function(String status)? onStatusUpdate;

  /// Called once on app start. Requests permission, checks hardware, initializes baseline, reads steps.
  Future<void> init(String uid) async {
    _currentUid = uid;

    // Listen for real-time hardware step events pushed from Android
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRawStepsChanged') {
        final raw = (call.arguments['rawSteps'] as num?)?.toInt() ?? 0;
        final date = call.arguments['stepDate'] as String? ?? '';
        if (_currentUid != null && raw > 0) {
          await _processRawSteps(raw, date, _currentUid!);
        }
      }
    });

    // 1. Check if device has hardware TYPE_STEP_COUNTER
    try {
      final available = await _channel.invokeMethod<bool>('isStepSensorAvailable');
      if (available == false) {
        _hasHardwareSensor = false;
        _isAvailable = false;
        debugPrint('[Steps] Hardware step counter not available on this device');
        onStatusUpdate?.call('Hardware step counter not available on this device');
        return;
      }
    } catch (_) {}

    // 2. Check and request activity recognition permission (required on Android 10+)
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      status = await Permission.activityRecognition.request();
    }
    if (!status.isGranted) {
      _isAvailable = false;
      debugPrint('[Steps] Activity recognition permission not granted');
      onStatusUpdate?.call('Activity recognition permission required to track steps');
      return;
    }

    _isAvailable = true;

    // 3. Re-init native sensor listener now that permission is confirmed granted
    try {
      await _channel.invokeMethod('setCurrentUid', {'uid': uid});
      await _channel.invokeMethod('reinitStepSensor');
    } catch (_) {}

    // 4. Read current accumulated hardware steps and update UI
    await _readAndUpdate(uid);

    // 5. Periodic refresh while app is active
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_currentUid != null) await _readAndUpdate(_currentUid!);
    });
  }

  /// Called on app resume (from WidgetsBindingObserver). Immediately syncs steps.
  Future<void> reinit() async {
    if (_currentUid == null) return;
    try {
      await _channel.invokeMethod('reinitStepSensor');
    } catch (_) {}
    await _readAndUpdate(_currentUid!);
  }

  /// Explicit on-demand refresh (Pull-to-Refresh on Home / Steps screen).
  /// Flushes hardware sensor FIFO queue and recalculates today's steps.
  Future<void> refreshSteps({String? uid}) async {
    final effectiveUid = uid ?? _currentUid;
    if (effectiveUid == null) return;

    try {
      // 1. Attempt hardware flush and read latest accumulated steps
      Map<dynamic, dynamic>? result;
      try {
        result = await _channel.invokeMethod<Map<dynamic, dynamic>>('forceRefreshSteps');
      } catch (_) {
        result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAccumulatedSteps');
      }

      if (result != null) {
        final rawSteps = (result['rawSteps'] as num?)?.toInt() ?? 0;
        final nativeDate = result['stepDate'] as String? ?? '';
        if (rawSteps > 0) {
          await _processRawSteps(rawSteps, nativeDate, effectiveUid);
        }
      }
    } catch (e) {
      debugPrint('[Steps] Error during refreshSteps: $e');
    }
  }

  /// Core logic: read raw steps from native SharedPreferences / hardware sensor.
  Future<void> _readAndUpdate(String uid) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAccumulatedSteps');
      if (result == null) return;

      final rawSteps = (result['rawSteps'] as num?)?.toInt() ?? 0;
      final nativeDate = result['stepDate'] as String? ?? '';
      await _processRawSteps(rawSteps, nativeDate, uid);
    } catch (e) {
      debugPrint('[Steps] Error reading accumulated steps: $e');
    }
  }

  String _getCanonicalDate([DateTime? dt]) {
    final d = dt ?? DateTime.now();
    final year = d.year.toString().padLeft(4, '0');
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _processRawSteps(int rawSteps, String nativeDate, String uid) async {
    try {
      if (rawSteps <= 0) return; // Do not initialize baseline with 0 if sensor hasn't reported yet

      final todayStr = _getCanonicalDate();
      final prefs = await SharedPreferences.getInstance();

      final baselineKey = 'grow_dart_baseline_$todayStr';
      final preRebootKey = 'grow_dart_pre_reboot_$todayStr';
      final lastRawKey = 'grow_dart_last_raw_$todayStr';

      // ── Handle day boundary rollover (in-session or across restarts) ─────
      final savedLastKnownDate = prefs.getString('grow_dart_last_known_date') ?? _lastKnownDate;
      if (savedLastKnownDate != null && savedLastKnownDate != todayStr) {
        debugPrint('[Steps] Day boundary rollover detected: $savedLastKnownDate -> $todayStr');
        // Finalize yesterday's record in SQLite
        if (_todaySteps > 0) {
          final yesterdayRecord = await _db.getStepRecord(uid, savedLastKnownDate);
          final goal = yesterdayRecord?.goal ?? 6000;
          await _db.upsertStepRecord(StepRecord(
            id: yesterdayRecord?.id,
            uid: uid,
            date: savedLastKnownDate,
            stepCount: _todaySteps,
            goal: goal,
          ));
        }

        // Reset today's steps in memory for the new day
        _todaySteps = 0;
        onStepUpdate?.call(0);

        // Reset baseline for the new day to current hardware total
        await prefs.setInt(baselineKey, rawSteps);
        await prefs.setInt(preRebootKey, 0);
        await prefs.setString('grow_dart_last_known_date', todayStr);
        await _channel.invokeMethod('setStepBaseline', {
          'date': todayStr,
          'baseline': rawSteps,
        });

        // Initialize today's record in SQLite with 0 steps
        final current = await _db.getStepRecord(uid, todayStr);
        await _db.upsertStepRecord(StepRecord(
          id: current?.id,
          uid: uid,
          date: todayStr,
          stepCount: 0,
          goal: current?.goal ?? 6000,
        ));
      }
      _lastKnownDate = todayStr;
      await prefs.setString('grow_dart_last_known_date', todayStr);

      // ── Baseline & Reboot calculation ────────────────────────────────────
      int baseline = prefs.getInt(baselineKey) ?? -1;
      int preReboot = prefs.getInt(preRebootKey) ?? 0;
      int lastRaw = prefs.getInt(lastRawKey) ?? rawSteps;

      if (baseline < 0) {
        // Check if native background worker already set a baseline for today
        int? nativeBaseline;
        try {
          final nb = await _channel.invokeMethod<num>('getStepBaseline', {'date': todayStr});
          if (nb != null && nb.toInt() > 0) {
            nativeBaseline = nb.toInt();
          }
        } catch (_) {}

        baseline = nativeBaseline ?? rawSteps;
        await prefs.setInt(baselineKey, baseline);
        await _channel.invokeMethod('setStepBaseline', {
          'date': todayStr,
          'baseline': baseline,
        });
      }

      // Guard: if device rebooted, rawSteps reset to 0 in hardware (rawSteps < baseline)
      if (rawSteps < baseline) {
        // Accumulate steps achieved prior to reboot
        final stepsBeforeReboot = lastRaw >= baseline ? (lastRaw - baseline) : 0;
        preReboot += stepsBeforeReboot;
        await prefs.setInt(preRebootKey, preReboot);

        // Reset baseline to 0 for post-reboot counting
        baseline = 0;
        await prefs.setInt(baselineKey, 0);
        await _channel.invokeMethod('setStepBaseline', {'date': todayStr, 'baseline': 0});
      }

      await prefs.setInt(lastRawKey, rawSteps);

      int calculatedToday = (rawSteps - baseline) + preReboot;
      if (calculatedToday < 0) calculatedToday = 0;

      // Ensure steps are strictly monotonic non-decreasing for the same day,
      // but do NOT resurrect yesterday's steps if calculatedToday is 0
      final currentRecord = await _db.getStepRecord(uid, todayStr);
      final existingDbSteps = currentRecord?.stepCount ?? 0;
      if (existingDbSteps > calculatedToday && calculatedToday > 0) {
        calculatedToday = existingDbSteps;
        // Realign baseline so future increments build from this point
        baseline = rawSteps - calculatedToday + preReboot;
        await prefs.setInt(baselineKey, baseline);
        await _channel.invokeMethod('setStepBaseline', {
          'date': todayStr,
          'baseline': baseline,
        });
      }

      _todaySteps = calculatedToday;
      onStepUpdate?.call(_todaySteps);

      // ── Persist to SQLite (enforcing 1 canonical row per calendar date) ───
      final goal = currentRecord?.goal ?? 6000;
      await _db.upsertStepRecord(StepRecord(
        id: currentRecord?.id,
        uid: uid,
        date: todayStr,
        stepCount: _todaySteps,
        goal: goal,
      ));
    } catch (e) {
      debugPrint('[Steps] Error processing raw steps: $e');
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}