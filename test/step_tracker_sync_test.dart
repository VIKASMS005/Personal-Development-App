import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/services/step_tracker_service.dart';

/// Verifies that the Flutter side only mirrors the native single source of truth:
/// whatever native reports (the same value the notification renders) is what the app
/// shows, pushes arrive in order, and stale/out-of-order values never lower the count.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.grow.app/settings');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Native state: what StepRepository would hold (and render in the notification).
  var nativeSteps = 0;
  var nativeDate = '2026-10-06';
  final calls = <String>[];

  Map<String, Object> snapshot() =>
      {'steps': nativeSteps, 'stepDate': nativeDate, 'goal': 6000};

  Future<void> pushFromNative() async {
    final data = const StandardMethodCodec()
        .encodeMethodCall(MethodCall('onStepsChanged', snapshot()));
    await messenger.handlePlatformMessage(channel.name, data, (_) {});
  }

  setUpAll(() async {
    messenger.setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'checkPermissionStatus') return 1; // granted
      if (call.method == 'requestPermissions') return {19: 1};
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isStepSensorAvailable':
          return true;
        case 'getTodaySteps':
        case 'forceRefreshSteps':
          return snapshot();
        case 'addManualSteps':
          nativeSteps += (call.arguments['steps'] as num).toInt();
          return snapshot();
      }
      return null;
    });
    nativeSteps = 1200;
    await StepTrackerService.instance.init('u1');
  });

  tearDownAll(() => StepTrackerService.instance.dispose());

  test('init reads the native (notification) value and starts one service', () {
    expect(StepTrackerService.instance.todaySteps, 1200);
    expect(calls.where((c) => c == 'startStepTrackingService').length, 1);
  });

  test('native pushes update the app value immediately and identically', () async {
    final seen = <int>[];
    StepTrackerService.instance.onStepUpdate = seen.add;
    for (final s in [1201, 1210, 1250]) {
      nativeSteps = s;
      await pushFromNative();
    }
    expect(seen, [1201, 1210, 1250]);
    expect(StepTrackerService.instance.todaySteps, nativeSteps);
  });

  test('an older/smaller value on the same day never overwrites a newer one', () async {
    nativeSteps = 1300;
    await pushFromNative();
    nativeSteps = 1100; // stale reply arriving late
    await pushFromNative();
    expect(StepTrackerService.instance.todaySteps, 1300);
  });

  test('re-init on resume / repeated init does not reset the count', () async {
    nativeSteps = 1300;
    await StepTrackerService.instance.reinit();
    await StepTrackerService.instance.init('u1');
    expect(StepTrackerService.instance.todaySteps, 1300);
    expect(calls.where((c) => c == 'startStepTrackingService').length, 2,
        reason: 'start is idempotent natively; Dart creates no extra counters');
  });

  test('manual steps go through native and come back as the shared value', () async {
    final total = await StepTrackerService.instance.addManualSteps(200);
    expect(total, 1500);
    expect(nativeSteps, 1500);
  });

  test('midnight is the only time the value may go down', () async {
    nativeDate = '2026-10-07';
    nativeSteps = 0;
    await pushFromNative();
    expect(StepTrackerService.instance.todaySteps, 0);
    expect(StepTrackerService.instance.todayDate, '2026-10-07');

    // A late push for the previous day must not bring yesterday back.
    final late = const StandardMethodCodec().encodeMethodCall(const MethodCall(
        'onStepsChanged', {'steps': 1500, 'stepDate': '2026-10-06', 'goal': 6000}));
    await messenger.handlePlatformMessage(channel.name, late, (_) {});
    expect(StepTrackerService.instance.todaySteps, 0);
  });
}
