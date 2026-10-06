import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// StepTrackerService — Flutter-side *reader* of the native step count.
///
/// Single source of truth:
///   The native `StepRepository` (Kotlin) owns today's step count. It is fed only by the
///   foreground `StepTrackingService`, validates steps, persists them, writes the
///   `step_records` row and drives the notification. This class does NOT calculate,
///   baseline, or persist steps; it only mirrors the native value so the app UI, the
///   notification and the database always show the same number.
///
///   Native → Dart: `onStepsChanged` pushes {steps, stepDate, goal} on every change.
///   Dart → Native: `getTodaySteps` / `forceRefreshSteps` read the same snapshot.
class StepTrackerService {
  static final StepTrackerService instance = StepTrackerService._internal();
  StepTrackerService._internal();

  static const _channel = MethodChannel('com.grow.app/settings');

  int _todaySteps = 0;
  String? _todayDate;
  bool _isAvailable = true;
  bool _hasHardwareSensor = true;
  String? _currentUid;
  bool _handlerRegistered = false;

  // Safety-net refresh while the app is active (native also pushes every change).
  Timer? _pollTimer;

  int get todaySteps => _todaySteps;
  String? get todayDate => _todayDate;
  bool get isAvailable => _isAvailable;
  bool get hasHardwareSensor => _hasHardwareSensor;

  Function(int steps)? onStepUpdate;
  Function(String status)? onStatusUpdate;

  /// Called on app start / account switch. Requests permission, starts the native service
  /// and reads the current count.
  Future<void> init(String uid) async {
    _currentUid = uid;

    if (!_handlerRegistered) {
      _handlerRegistered = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onStepsChanged') {
          _applySnapshot(call.arguments);
        }
      });
    }

    // 1. Check that the device has a step sensor
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

    // 2. Activity recognition permission (required on Android 10+)
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

    // 3. Start the single native tracking service (idempotent)
    try {
      await _channel.invokeMethod('setCurrentUid', {'uid': uid});
      await _channel.invokeMethod('startStepTrackingService');
    } catch (_) {}

    // 4. Read the authoritative value
    await _read('getTodaySteps');

    // 5. Safety-net refresh — cancel any old timer first so there is only ever one
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _read('getTodaySteps');
    });
  }

  /// Called on app resume. Makes sure the service is running and re-reads the count.
  Future<void> reinit() async {
    if (_currentUid == null) return;
    try {
      await _channel.invokeMethod('reinitStepSensor');
    } catch (_) {}
    await _read('getTodaySteps');
  }

  /// Explicit on-demand refresh (pull-to-refresh). Asks native to flush batched sensor
  /// events; the fresh value also arrives through `onStepsChanged`.
  Future<void> refreshSteps({String? uid}) async {
    if ((uid ?? _currentUid) == null) return;
    await _read('forceRefreshSteps');
  }

  /// Add manually logged steps. Native adds them to the same authoritative count, so the
  /// sensor can never overwrite them.
  Future<int> addManualSteps(int steps) async {
    try {
      final res = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('addManualSteps', {'steps': steps});
      _applySnapshot(res);
    } catch (e) {
      debugPrint('[Steps] addManualSteps error: $e');
    }
    return _todaySteps;
  }

  /// Push the user's chosen step goal to native (used by the notification and DB rows).
  Future<void> setNativeStepGoal(int goal) async {
    try {
      await _channel.invokeMethod('setStepGoal', {'goal': goal});
    } catch (e) {
      debugPrint('[Steps] setNativeStepGoal error: $e');
    }
  }

  Future<void> _read(String method) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(method);
      _applySnapshot(res);
    } catch (e) {
      debugPrint('[Steps] Error reading steps ($method): $e');
    }
  }

  void _applySnapshot(dynamic args) {
    if (args is! Map) return;
    final steps = (args['steps'] as num?)?.toInt();
    final date = args['stepDate'] as String?;
    if (steps == null || date == null) return;
    // Native is monotonic within a day; ignore an out-of-order older reply.
    if (_todayDate != null && date.compareTo(_todayDate!) < 0) return;
    if (date == _todayDate && steps < _todaySteps) return;
    if (date == _todayDate && steps == _todaySteps) return;
    _todayDate = date;
    _todaySteps = steps;
    onStepUpdate?.call(steps);
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
