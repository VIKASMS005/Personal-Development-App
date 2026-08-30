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
///      in low-power silicon continuously from boot (including when phone is locked/asleep).
///   2. MainActivity registers the sensor listener silently (no foreground notification).
///   3. On app start, resume, or periodic refresh, StepTrackerService reads the hardware count
///      and calculates `todaySteps = rawSteps - baselineForToday`.
///   4. Saves to SQLite and SharedPreferences atomically.
class StepTrackerService {
  static final StepTrackerService instance = StepTrackerService._internal();
  StepTrackerService._internal();

  static const _channel = MethodChannel('com.grow.app/settings');
  final DatabaseService _db = DatabaseService.instance;

  int _todaySteps = 0;
  bool _isAvailable = true;
  String? _currentUid;
  String? _lastKnownDate;

  // Polling timer — refreshes hardware count every 15 seconds while app is active
  Timer? _pollTimer;

  int get todaySteps => _todaySteps;
  bool get isAvailable => _isAvailable;

  Function(int steps)? onStepUpdate;
  Function(String status)? onStatusUpdate;

  /// Called once on app start. Requests permission, initializes baseline, reads steps.
  Future<void> init(String uid) async {
    _currentUid = uid;

    // 1. Request activity recognition permission (required on Android 10+)
    final status = await Permission.activityRecognition.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      _isAvailable = false;
      debugPrint('[Steps] Activity recognition permission denied');
      return;
    }

    // 2. Read current accumulated hardware steps and update UI
    await _readAndUpdate(uid);

    // 3. Periodic refresh while app is active
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_currentUid != null) await _readAndUpdate(_currentUid!);
    });
  }

  /// Called on app resume (from WidgetsBindingObserver). Immediately syncs steps.
  Future<void> reinit() async {
    if (_currentUid == null || !_isAvailable) return;
    await _readAndUpdate(_currentUid!);
  }

  /// Core logic: read raw steps from native SharedPreferences / hardware sensor.
  Future<void> _readAndUpdate(String uid) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getAccumulatedSteps');
      if (result == null) return;

      final rawSteps = (result['rawSteps'] as num?)?.toInt() ?? -1;
      final nativeDate = result['stepDate'] as String? ?? '';

      if (rawSteps < 0) return; // Hardware sensor warming up

      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final prefs = await SharedPreferences.getInstance();

      // ── Handle day boundary ──────────────────────────────────────────────
      if (nativeDate != todayStr || _lastKnownDate != todayStr) {
        final baselineKey = 'grow_dart_baseline_$todayStr';
        final existingBaseline = prefs.getInt(baselineKey) ?? -1;
        if (existingBaseline < 0) {
          await prefs.setInt(baselineKey, rawSteps);
          await _channel.invokeMethod('setStepBaseline', {
            'date': todayStr,
            'baseline': rawSteps,
          });
        }
        _lastKnownDate = todayStr;
      }

      // ── Compute today's steps ────────────────────────────────────────────
      final baselineKey = 'grow_dart_baseline_$todayStr';
      int baseline = prefs.getInt(baselineKey) ?? -1;

      if (baseline < 0) {
        baseline = rawSteps;
        await prefs.setInt(baselineKey, rawSteps);
        await _channel.invokeMethod('setStepBaseline', {
          'date': todayStr,
          'baseline': rawSteps,
        });
      }

      int calculatedToday = rawSteps - baseline;

      // Guard: if device rebooted, rawSteps reset to 0 in hardware (rawSteps < baseline)
      if (calculatedToday < 0) {
        calculatedToday = rawSteps;
        await prefs.setInt(baselineKey, 0);
        await _channel.invokeMethod('setStepBaseline', {'date': todayStr, 'baseline': 0});
      }

      if (calculatedToday == _todaySteps) return;

      _todaySteps = calculatedToday;
      onStepUpdate?.call(_todaySteps);

      // ── Persist to SQLite ────────────────────────────────────────────────
      final currentRecord = await _db.getStepRecord(uid, todayStr);
      final goal = currentRecord?.goal ?? 6000;
      await _db.upsertStepRecord(StepRecord(
        id: currentRecord?.id,
        uid: uid,
        date: todayStr,
        stepCount: _todaySteps,
        goal: goal,
      ));
    } catch (e) {
      debugPrint('[Steps] Error reading accumulated steps: $e');
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}