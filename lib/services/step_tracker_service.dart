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
  bool _initialized = false; // FIX H2: prevent duplicate init on repeated calls

  // Polling timer — refreshes hardware count every 15 seconds while app is active
  Timer? _pollTimer;

  int get todaySteps => _todaySteps;
  bool get isAvailable => _isAvailable;
  bool get hasHardwareSensor => _hasHardwareSensor;

  Function(int steps)? onStepUpdate;
  Function(String status)? onStatusUpdate;

  /// Called once on app start. Requests permission, checks hardware, initializes baseline, reads steps.
  Future<void> init(String uid) async {
    // FIX H2: Only register the method call handler once. If UID changes (e.g.,
    // account switch), allow full re-init. Otherwise skip to avoid duplicate timers.
    final uidChanged = uid != _currentUid;
    _currentUid = uid;

    if (!_initialized || uidChanged) {
      _initialized = true;

      // Listen for real-time hardware step events pushed from Android
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onRawStepsChanged') {
          final raw = (call.arguments['rawSteps'] as num?)?.toInt() ?? 0;
          final date = call.arguments['stepDate'] as String? ?? '';
          final discarded = (call.arguments['discardedSteps'] as num?)?.toInt() ?? 0;
          if (_currentUid != null && raw > 0) {
            await _processRawSteps(raw, date, _currentUid!, nativeDiscarded: discarded);
          }
        }
      });
    }

    // 1. Check if device has hardware TYPE_STEP_COUNTER
    try {
      final available =
          await _channel.invokeMethod<bool>('isStepSensorAvailable');
      if (available == false) {
        _hasHardwareSensor = false;
        _isAvailable = false;
        debugPrint(
            '[Steps] Hardware step counter not available on this device');
        onStatusUpdate
            ?.call('Hardware step counter not available on this device');
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
      onStatusUpdate
          ?.call('Activity recognition permission required to track steps');
      return;
    }

    _isAvailable = true;

    // 3. Re-init native sensor listener now that permission is confirmed granted
    try {
      await _channel.invokeMethod('setCurrentUid', {'uid': uid});
      await _channel.invokeMethod('startStepTrackingService');
      await _channel.invokeMethod('reinitStepSensor');
    } catch (_) {}

    // 4. Read current accumulated hardware steps and update UI
    await _readAndUpdate(uid);

    // 5. Periodic refresh while app is active — cancel old timer first to prevent duplicates
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
        result = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('forceRefreshSteps');
      } catch (_) {
        result = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('getAccumulatedSteps');
      }

      if (result != null) {
        final rawSteps = (result['rawSteps'] as num?)?.toInt() ?? 0;
        final nativeDate = result['stepDate'] as String? ?? '';
        final discarded = (result['discardedSteps'] as num?)?.toInt() ?? 0;
        if (rawSteps > 0) {
          await _processRawSteps(rawSteps, nativeDate, effectiveUid, nativeDiscarded: discarded);
        }
      }
    } catch (e) {
      debugPrint('[Steps] Error during refreshSteps: $e');
    }
  }

  /// Core logic: read raw steps from native SharedPreferences / hardware sensor.
  Future<void> _readAndUpdate(String uid) async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getAccumulatedSteps');
      if (result == null) return;

      final rawSteps = (result['rawSteps'] as num?)?.toInt() ?? 0;
      final nativeDate = result['stepDate'] as String? ?? '';
      final discarded = (result['discardedSteps'] as num?)?.toInt() ?? 0;
      await _processRawSteps(rawSteps, nativeDate, uid, nativeDiscarded: discarded);
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

  Future<void> _processRawSteps(
      int rawSteps, String nativeDate, String uid, {int nativeDiscarded = 0}) async {
    try {
      if (rawSteps <= 0) {
        return; // Do not initialize baseline with 0 if sensor hasn't reported yet
      }

      final parsedNativeDate = DateTime.tryParse(nativeDate);
      final todayStr = parsedNativeDate == null
          ? _getCanonicalDate()
          : _getCanonicalDate(parsedNativeDate);
      final prefs = await SharedPreferences.getInstance();

      // FIX C2: Read user's chosen goal from SharedPreferences instead of ?? 6000.
      // This ensures the goal the user set (e.g. 10,000) is always used.
      final userGoal = prefs.getInt('grow_daily_step_goal') ?? 6000;

      final baselineKey = 'grow_dart_baseline_$todayStr';
      final preRebootKey = 'grow_dart_pre_reboot_$todayStr';
      final lastRawKey = 'grow_dart_last_raw_$todayStr';

      // ── Handle day boundary rollover (in-session or across restarts) ─────
      final savedLastKnownDate =
          prefs.getString('grow_dart_last_known_date') ?? _lastKnownDate;
      if (savedLastKnownDate != null && savedLastKnownDate != todayStr) {
        debugPrint(
            '[Steps] Day boundary rollover detected: $savedLastKnownDate -> $todayStr');
        // Finalize yesterday's record in SQLite — use its own goal if it already exists
        if (_todaySteps > 0) {
          final yesterdayRecord =
              await _db.getStepRecord(uid, savedLastKnownDate);
          // Use the goal already stored in yesterday's record (the one the user had set then),
          // falling back to the current user goal — never blindly to 6000.
          final yesterdayGoal =
              (yesterdayRecord?.goal != null && yesterdayRecord!.goal > 0)
                  ? yesterdayRecord.goal
                  : userGoal;
          await _db.upsertStepRecord(StepRecord(
            id: yesterdayRecord?.id,
            uid: uid,
            date: savedLastKnownDate,
            stepCount: _todaySteps,
            goal: yesterdayGoal,
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

        // Initialize today's record in SQLite with 0 steps, using user's actual goal
        final current = await _db.getStepRecord(uid, todayStr);
        final todayGoal = (current?.goal != null && current!.goal > 0)
            ? current.goal
            : userGoal;
        await _db.upsertStepRecord(StepRecord(
          id: current?.id,
          uid: uid,
          date: todayStr,
          stepCount: 0,
          goal: todayGoal,
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
          final nb = await _channel
              .invokeMethod<num>('getStepBaseline', {'date': todayStr});
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
        final stepsBeforeReboot =
            lastRaw >= baseline ? (lastRaw - baseline) : 0;

        // BUG 2 FIX: Also pick up the pre-reboot offset written by BootReceiver.kt
        // so steps counted before the reboot are never lost even on first cold start.
        int nativeBootOffset = 0;
        try {
          final nb = await _channel
              .invokeMethod<num>('getPreRebootOffset', {'date': todayStr});
          if (nb != null) nativeBootOffset = nb.toInt();
        } catch (_) {}

        preReboot += stepsBeforeReboot + nativeBootOffset;
        await prefs.setInt(preRebootKey, preReboot);

        // Reset baseline to 0 for post-reboot counting
        baseline = 0;
        await prefs.setInt(baselineKey, 0);
        await _channel
            .invokeMethod('setStepBaseline', {'date': todayStr, 'baseline': 0});
      }

      await prefs.setInt(lastRawKey, rawSteps);

      int calculatedToday = (rawSteps - baseline) + preReboot;
      if (calculatedToday < 0) calculatedToday = 0;

      // Subtract steps discarded by the native gait validator.
      // nativeDiscarded comes directly from the native side's SharedPreferences
      // (passed via MethodChannel) — this is the authoritative count of false
      // positives detected by the GaitValidator (phone shaking, leg bouncing, etc.)
      int discardedSteps = nativeDiscarded;
      final cleanupDone = prefs.getBool('grow_cleanup_v6_done') ?? false;
      if (!cleanupDone) {
        await prefs.setInt('grow_discarded_steps_$todayStr', 0);
        await prefs.setBool('grow_cleanup_v6_done', true);
        discardedSteps = 0;
      } else if (discardedSteps <= 0) {
        // Fallback: query native directly if not passed in (e.g. legacy code path)
        try {
          final nd = await _channel
              .invokeMethod<num>('getDiscardedSteps', {'date': todayStr});
          if (nd != null && nd.toInt() > 0) discardedSteps = nd.toInt();
        } catch (_) {}
      }
      calculatedToday = (calculatedToday - discardedSteps).clamp(0, calculatedToday);

      // Read current DB record for goal preservation
      final currentRecord = await _db.getStepRecord(uid, todayStr);

      // NOTE: We deliberately do NOT apply a monotonic non-decreasing guard here.
      // The native gait validator may INCREASE discardedSteps over time as it
      // detects more false positives, which correctly DECREASES calculatedToday.
      // A monotonic guard would lock in false step counts and defeat the validator.

      _todaySteps = calculatedToday;
      onStepUpdate?.call(_todaySteps);

      // ── Persist to SQLite — always use user's chosen goal, never 6000 blindly ───
      // If the DB record already has a non-zero goal (user may have set it via the goal dialog),
      // preserve it. Otherwise use the SharedPreferences goal.
      final persistGoal =
          (currentRecord?.goal != null && currentRecord!.goal > 0)
              ? currentRecord.goal
              : userGoal;
      await _db.upsertStepRecord(StepRecord(
        id: currentRecord?.id,
        uid: uid,
        date: todayStr,
        stepCount: _todaySteps,
        goal: persistGoal,
      ));
    } catch (e) {
      debugPrint('[Steps] Error processing raw steps: $e');
    }
  }

  /// BUG 3 FIX: Lower the baseline by [steps] on both the native and Dart side
  /// after manual steps are added, so the formula `todaySteps = rawSteps - baseline`
  /// naturally incorporates the manual addition and the sensor never overwrites it.
  Future<void> adjustManualStepsBaseline(int steps, String todayStr) async {
    try {
      // 1. Lower native (Kotlin) baseline
      await _channel.invokeMethod('adjustStepBaseline', {
        'date': todayStr,
        'delta': steps,
      });

      // 2. Lower Dart-side baseline in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final baselineKey = 'grow_dart_baseline_$todayStr';
      final preRebootKey = 'grow_dart_pre_reboot_$todayStr';
      final current = prefs.getInt(baselineKey) ?? 0;
      final newBaseline = (current - steps).clamp(0, current);
      await prefs.setInt(baselineKey, newBaseline);
      if (steps > current) {
        final remainder = steps - current;
        final currentPre = prefs.getInt(preRebootKey) ?? 0;
        await prefs.setInt(preRebootKey, currentPre + remainder);
      }
    } catch (e) {
      debugPrint('[Steps] adjustManualStepsBaseline error: $e');
    }
  }

  /// FIX C2: Push the user's chosen step goal to native (Kotlin) SharedPreferences.
  /// Called by StepProvider.updateDailyGoal() so background workers (StepDbHelper,
  /// DailyStepWorker) can read the correct goal when inserting new day rows.
  Future<void> setNativeStepGoal(int goal) async {
    try {
      await _channel.invokeMethod('setStepGoal', {'goal': goal});
    } catch (e) {
      debugPrint('[Steps] setNativeStepGoal error: $e');
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
