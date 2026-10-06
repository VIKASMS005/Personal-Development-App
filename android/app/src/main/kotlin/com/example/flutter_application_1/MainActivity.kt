package com.example.flutter_application_1

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorEventListener2
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity(), SensorEventListener2 {
    private val TAG = "GrowMainActivity"
    private val CHANNEL = "com.grow.app/settings"
    private val PREFS_NAME = "grow_step_prefs"
    private val KEY_RAW_STEPS = "grow_raw_steps"
    private val KEY_STEP_DATE = "grow_step_date"
    private val KEY_BASELINE_PREFIX = "grow_baseline_"
    private val KEY_CURRENT_UID = "grow_current_uid"

    private var sensorManager: SensorManager? = null
    private var stepSensor: Sensor? = null
    private var stepDetectorSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var lastRawStepCount: Long = 0L
    private var lastHardwareCounterRaw: Long = 0L
    private var detectorStepsSinceCounter: Long = 0L
    private var methodChannel: MethodChannel? = null
    private val pendingStepResults = mutableListOf<MethodChannel.Result>()

    // Gait validation engine — prevents false steps from phone shaking
    private val gaitValidator = GaitValidator()
    private var lastValidatedRaw = 0L
    private var discardedStepsToday = 0L
    private var hasReceivedStepEvent = false
    private val validationHandler = Handler(Looper.getMainLooper())
    private val validationRunnable = object : Runnable {
        override fun run() {
            performStepValidation()
            validationHandler.postDelayed(this, 10_000L)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize hardware step sensor listener (silent — no notification)
        initStepSensor()

        // Schedule background step synchronization & midnight roll-over snapshots
        StepBackgroundManager.schedulePeriodicSync(this)
        StepBackgroundManager.scheduleMidnightAlarm(this)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Settings navigation ──────────────────────────────────
                    "openUsageAccessSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                                .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                        )
                        result.success(null)
                    }
                    "openBatteryOptimizationSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                        )
                        result.success(null)
                    }

                    // ── App metadata & Icons ─────────────────────────────────
                    "getAppInfo" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != null) {
                            result.success(getSingleAppInfo(packageName))
                        } else {
                            result.error("INVALID_ARG", "packageName is required", null)
                        }
                    }
                    "getBatchAppInfo" -> {
                        val packageNames = call.argument<List<String>>("packages") ?: emptyList()
                        val responseMap = HashMap<String, Map<String, String>>()
                        for (pkg in packageNames) {
                            val info = getSingleAppInfo(pkg)
                            if (info != null) responseMap[pkg] = info
                        }
                        result.success(responseMap)
                    }
                    "getDeviceTimeZone" -> {
                        val tzId = java.util.TimeZone.getDefault().id
                        result.success(tzId)
                    }

                    // ── Step Counter (Hardware sensor — silent, no notification) ──
                    "isStepSensorAvailable" -> {
                        val available = (stepSensor != null)
                        result.success(available)
                    }
                    "reinitStepSensor" -> {
                        initStepSensor()
                        try {
                            stepSensor?.let { sensorManager?.flush(this) }
                        } catch (_: Exception) {}
                        result.success(stepSensor != null)
                    }
                    "startStepTrackingService" -> {
                        StepTrackingService.start(this)
                        result.success(null)
                    }
                    "getAccumulatedSteps" -> {
                        val today = StepDbHelper.getLocalTodayString()
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

                        if (stepSensor != null) {
                            val handler = Handler(Looper.getMainLooper())
                            var answered = false

                            val finishRunnable = Runnable {
                                if (!answered) {
                                    answered = true
                                    val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
                                    val currentRaw = if (lastRawStepCount > 0L) lastRawStepCount else savedRaw
                                    if (currentRaw > 0L) {
                                        StepDbHelper.handleDateRollover(this, currentRaw, today)
                                    }
                                    result.success(mapOf("rawSteps" to currentRaw, "stepDate" to today, "discardedSteps" to getAuthoritativeDiscardedSteps(today)))
                                }
                            }

                            val flushCallback = object : MethodChannel.Result {
                                override fun success(res: Any?) {
                                    if (!answered) {
                                        answered = true
                                        handler.removeCallbacks(finishRunnable)
                                        result.success(res)
                                    }
                                }
                                override fun error(code: String, msg: String?, details: Any?) {
                                    if (!answered) {
                                        answered = true
                                        handler.removeCallbacks(finishRunnable)
                                        result.error(code, msg, details)
                                    }
                                }
                                override fun notImplemented() {
                                    if (!answered) {
                                        answered = true
                                        handler.removeCallbacks(finishRunnable)
                                        result.notImplemented()
                                    }
                                }
                            }
                            pendingStepResults.add(flushCallback)

                            try {
                                sensorManager?.flush(this)
                            } catch (_: Exception) {}

                            // Wait up to 120ms for flush; if already answered via onSensorChanged/onFlushCompleted, finishRunnable is cancelled
                            handler.postDelayed(finishRunnable, 120)
                        } else {
                            val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
                            val effectiveRaw = if (lastRawStepCount > 0L) lastRawStepCount else savedRaw
                            if (effectiveRaw > 0L) {
                                StepDbHelper.handleDateRollover(this, effectiveRaw, today)
                            }
                            result.success(mapOf("rawSteps" to effectiveRaw, "stepDate" to today, "discardedSteps" to getAuthoritativeDiscardedSteps(today)))
                        }
                    }
                    "forceRefreshSteps" -> {
                        val today = StepDbHelper.getLocalTodayString()
                        initStepSensor()

                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val handler = Handler(Looper.getMainLooper())
                        var answered = false

                        val finishRunnable = Runnable {
                            if (!answered) {
                                answered = true
                                val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
                                val finalRaw = if (lastRawStepCount > 0L) lastRawStepCount else savedRaw
                                if (finalRaw > 0L) {
                                    StepDbHelper.handleDateRollover(this, finalRaw, today)
                                }
                                result.success(mapOf("rawSteps" to finalRaw, "stepDate" to today, "discardedSteps" to getAuthoritativeDiscardedSteps(today)))
                            }
                        }

                        val flushCallback = object : MethodChannel.Result {
                            override fun success(res: Any?) {
                                if (!answered) {
                                    answered = true
                                    handler.removeCallbacks(finishRunnable)
                                    result.success(res)
                                }
                            }
                            override fun error(code: String, msg: String?, details: Any?) {
                                if (!answered) {
                                    answered = true
                                    handler.removeCallbacks(finishRunnable)
                                    result.error(code, msg, details)
                                }
                            }
                            override fun notImplemented() {
                                if (!answered) {
                                    answered = true
                                    handler.removeCallbacks(finishRunnable)
                                    result.notImplemented()
                                }
                            }
                        }
                        pendingStepResults.add(flushCallback)

                        try {
                            stepSensor?.let { sensorManager?.flush(this) }
                        } catch (_: Exception) {}

                        // Give flush 150ms to deliver any queued hardware FIFO sensor events to onSensorChanged
                        handler.postDelayed(finishRunnable, 150)
                    }
                    "getStepBaseline" -> {
                        val dateStr = call.argument<String>("date") ?: ""
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val baselineKey = KEY_BASELINE_PREFIX + dateStr
                        val baseline = if (prefs.contains(baselineKey)) prefs.getLong(baselineKey, -1L) else -1L
                        result.success(baseline)
                    }
                    "setStepBaseline" -> {
                        val dateStr = call.argument<String>("date") ?: ""
                        val baseline = (call.argument<Number>("baseline"))?.toLong() ?: -1L
                        if (dateStr.isNotEmpty() && baseline >= 0) {
                            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            prefs.edit()
                                .putLong(KEY_BASELINE_PREFIX + dateStr, baseline)
                                .commit()
                        }
                        result.success(null)
                    }
                    "setCurrentUid" -> {
                        val uid = call.argument<String>("uid") ?: "local_user"
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putString(KEY_CURRENT_UID, uid).apply()
                        result.success(null)
                    }

                    // BUG 2 FIX: Expose the pre-reboot offset saved by BootReceiver so Dart
                    // can include it in its preReboot accumulator after device restarts.
                    "getPreRebootOffset" -> {
                        val dateStr = call.argument<String>("date") ?: ""
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val offset = prefs.getLong("grow_pre_reboot_offset_$dateStr", 0L)
                        result.success(offset)
                    }

                    // BUG 3 FIX: Adjust (lower) the native baseline so that manually added steps
                    // are incorporated into the formula `todaySteps = rawSteps - baseline + preReboot`
                    // and are NOT erased by the next onSensorChanged callback.
                    "adjustStepBaseline" -> {
                        val dateStr = call.argument<String>("date") ?: ""
                        val delta = (call.argument<Number>("delta"))?.toLong() ?: 0L
                        if (dateStr.isNotEmpty() && delta > 0L) {
                            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            val key = KEY_BASELINE_PREFIX + dateStr
                            val current = prefs.getLong(key, 0L)
                            val newBaseline = maxOf(0L, current - delta)
                            val remainder = if (delta > current) (delta - current) else 0L
                            val editor = prefs.edit().putLong(key, newBaseline)
                            if (remainder > 0L) {
                                val currentOffset = prefs.getLong("grow_pre_reboot_offset_$dateStr", 0L)
                                editor.putLong("grow_pre_reboot_offset_$dateStr", currentOffset + remainder)
                            }
                            editor.commit()
                        }
                        result.success(null)
                    }

                    // FIX C2: Store user's step goal in native prefs so StepDbHelper and DailyStepWorker
                    // can read it when inserting new day rows, instead of defaulting to 6000.
                    "setStepGoal" -> {
                        val goal = (call.argument<Number>("goal"))?.toInt() ?: 6000
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putInt("grow_daily_step_goal", goal).commit()
                        result.success(null)
                    }

                    "getStepGoal" -> {
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val goal = prefs.getInt("grow_daily_step_goal", 6000)
                        result.success(goal)
                    }

                    // Gait validation: return count of discarded (false-positive) steps for a date
                    "getDiscardedSteps" -> {
                        val dateStr = call.argument<String>("date") ?: ""
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        val discarded = prefs.getLong("grow_discarded_steps_$dateStr", 0L)
                        result.success(discarded)
                    }

                    // ── UsageEvents-based Foreground Screen Time ─────────────
                    "getUsageEvents" -> {
                        val startMs = call.argument<Long>("startMs")
                        val endMs = call.argument<Long>("endMs")
                        if (startMs == null || endMs == null) {
                            result.error("INVALID_ARG", "startMs and endMs are required", null)
                            return@setMethodCallHandler
                        }
                        if (!hasUsagePermission()) {
                            result.error("NO_PERMISSION", "Usage access not granted", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val usageList = computeForegroundUsage(startMs, endMs)
                            result.success(usageList)
                        } catch (e: Exception) {
                            result.error("USAGE_ERROR", e.message, null)
                        }
                    }

                    "hasUsagePermission" -> {
                        result.success(hasUsagePermission())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Silent Hardware Step Sensor + Accelerometer for Gait Validation ────────
    private fun initStepSensor() {
        try {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            // Request the hardware wake-up step sensor so hardware FIFO interrupts wake the AP during deep sleep
            val wakeUpSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, true)
            stepSensor = wakeUpSensor ?: sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

            val detectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR, true)
                ?: sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
            stepDetectorSensor = detectorSensor

            // Pre-populate lastRawStepCount from storage so startup is instant
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
            if (savedRaw > 0L) {
                lastRawStepCount = savedRaw
            }

            // Load today's validation state
            val today = StepDbHelper.getLocalTodayString()
            val cleanupDone = prefs.getBoolean("grow_cleanup_v6_done", false)
            if (!cleanupDone) {
                // Reset any bogus discarded steps stored by previous overly-strict version
                prefs.edit()
                    .putLong("grow_discarded_steps_$today", 0L)
                    .putLong("grow_validated_offset_$today", 0L)
                    .putBoolean("grow_cleanup_v6_done", true)
                    .apply()
                discardedStepsToday = 0L
                lastValidatedRaw = 0L
            } else {
                discardedStepsToday = prefs.getLong("grow_discarded_steps_$today", 0L)
                lastValidatedRaw = prefs.getLong("grow_validated_offset_$today", 0L)
            }

            stepSensor?.let {
                // Register with 0 latency for instant foreground step delivery
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI, 0)
            }
            stepDetectorSensor?.let {
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI, 0)
            }

            // Register accelerometer for gait validation (~50Hz)
            accelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            accelSensor?.let {
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
            }

            // Start periodic validation timer (if not already running)
            validationHandler.removeCallbacks(validationRunnable)
            validationHandler.postDelayed(validationRunnable, 10_000L)
        } catch (e: Exception) {
            // Ignore if sensor not available
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        when (event.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> handleStepCounterEvent(event)
            Sensor.TYPE_STEP_DETECTOR -> handleStepDetectorEvent(event)
            Sensor.TYPE_ACCELEROMETER -> gaitValidator.addSample(event.values[0], event.values[1], event.values[2], event.timestamp)
        }
    }

    private fun getAuthoritativeDiscardedSteps(today: String): Long {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val discarded = prefs.getLong("grow_discarded_steps_$today", 0L)
        discardedStepsToday = discarded
        return discarded
    }

    /**
     * Handle TYPE_STEP_DETECTOR events.
     * Fires on EVERY single step with immediate low latency (< 50ms).
     * Advances real-time step counter immediately.
     */
    private fun handleStepDetectorEvent(event: SensorEvent) {
        gaitValidator.recordStepArrival(event.timestamp)

        detectorStepsSinceCounter++
        val effectiveRaw = if (lastHardwareCounterRaw > 0L) {
            lastHardwareCounterRaw + detectorStepsSinceCounter
        } else if (lastRawStepCount > 0L) {
            lastRawStepCount + detectorStepsSinceCounter
        } else {
            detectorStepsSinceCounter
        }
        dispatchRawStepsUpdate(effectiveRaw)
    }

    /**
     * Handle TYPE_STEP_COUNTER events.
     * Reports cumulative hardware counter. Reconciles with real-time detector
     * steps so there is ZERO double-counting.
     */
    private fun handleStepCounterEvent(event: SensorEvent) {
        val counterRaw = event.values[0].toLong()
        if (counterRaw <= 0L) return

        gaitValidator.recordStepArrival(event.timestamp)

        if (counterRaw > lastHardwareCounterRaw) {
            val totalEffective = maxOf(counterRaw, lastHardwareCounterRaw + detectorStepsSinceCounter)
            lastHardwareCounterRaw = counterRaw
            // Reconcile pending detector steps
            detectorStepsSinceCounter = maxOf(0L, totalEffective - counterRaw)
        } else if (lastHardwareCounterRaw == 0L) {
            lastHardwareCounterRaw = counterRaw
            detectorStepsSinceCounter = 0L
        }

        val effectiveRaw = lastHardwareCounterRaw + detectorStepsSinceCounter
        dispatchRawStepsUpdate(effectiveRaw)
    }

    /**
     * Common step event dispatch: records raw steps, handles date rollover,
     * fulfills pending queries, and pushes real-time update to Flutter.
     */
    private fun dispatchRawStepsUpdate(rawSteps: Long) {
        if (rawSteps <= 0L) return
        lastRawStepCount = rawSteps
        val today = StepDbHelper.getLocalTodayString()

        if (!hasReceivedStepEvent) {
            hasReceivedStepEvent = true
            if (lastValidatedRaw == 0L) {
                lastValidatedRaw = rawSteps
            }
        }

        // Check and process day rollover if calendar day changed
        StepDbHelper.handleDateRollover(this, rawSteps, today)

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(KEY_RAW_STEPS, rawSteps)
            .putString(KEY_STEP_DATE, today)
            .apply()

        // Complete any pending getAccumulatedSteps calls — include discarded count
        if (pendingStepResults.isNotEmpty()) {
            val callbacks = ArrayList(pendingStepResults)
            pendingStepResults.clear()
            val authoritativeDiscarded = getAuthoritativeDiscardedSteps(today)
            for (cb in callbacks) {
                cb.success(mapOf(
                    "rawSteps" to rawSteps,
                    "stepDate" to today,
                    "discardedSteps" to authoritativeDiscarded
                ))
            }
        }

        // Push real-time step event to Flutter WITH authoritative discarded count
        val authoritativeDiscarded = getAuthoritativeDiscardedSteps(today)
        runOnUiThread {
            methodChannel?.invokeMethod("onRawStepsChanged", mapOf(
                "rawSteps" to rawSteps,
                "stepDate" to today,
                "discardedSteps" to authoritativeDiscarded
            ))
        }
    }

    /**
     * Periodic validation: Analyze gait data and decide whether quarantined steps
     * are genuine walking or false positives from phone shaking.
     */
    private fun performStepValidation() {
        if (!hasReceivedStepEvent || lastRawStepCount <= 0L) return

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val today = StepDbHelper.getLocalTodayString()
        val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"

        // Sync with SharedPreferences (which may be updated by StepTrackingService)
        val savedValidatedRaw = prefs.getLong("grow_validated_offset_$today", 0L)
        if (savedValidatedRaw > 0L) {
            lastValidatedRaw = maxOf(lastValidatedRaw, savedValidatedRaw)
        }
        discardedStepsToday = prefs.getLong("grow_discarded_steps_$today", 0L)

        // How many raw steps since last validation checkpoint?
        val rawDelta = lastRawStepCount - lastValidatedRaw
        if (rawDelta <= 0) return

        // Run shaking / fraud analysis
        gaitValidator.analyze()

        if (gaitValidator.isShakingMotion()) {
            // Shaking detected — discard false steps
            discardedStepsToday += rawDelta
            lastValidatedRaw = lastRawStepCount
            Log.d(TAG, "MainActivity DISCARDED $rawDelta steps as SHAKING (discarded_today=$discardedStepsToday)")
        } else {
            // Genuine walking or background pedometer tracking — accept steps!
            lastValidatedRaw = lastRawStepCount
            Log.d(TAG, "MainActivity ACCEPTED $rawDelta steps (genuine walking)")
        }

        // Save validation state
        prefs.edit()
            .putLong("grow_discarded_steps_$today", discardedStepsToday)
            .putLong("grow_validated_offset_$today", lastValidatedRaw)
            .apply()

        // Write validated step count to SQLite
        val todayBaseline = prefs.getLong(KEY_BASELINE_PREFIX + today, -1L)
        if (todayBaseline >= 0L && lastRawStepCount >= todayBaseline) {
            val totalRawDelta = lastRawStepCount - todayBaseline
            val validatedSteps = maxOf(0L, totalRawDelta - discardedStepsToday)
            StepDbHelper.writeStepRecord(this, uid, today, validatedSteps)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onFlushCompleted(sensor: Sensor?) {
        if (sensor?.type != Sensor.TYPE_STEP_COUNTER) return

        val today = StepDbHelper.getLocalTodayString()
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
        val currentRaw = if (lastRawStepCount > 0L) lastRawStepCount else savedRaw

        // BUG 8 FIX: Ensure date rollover is checked here too.
        // If the user opens the app right after midnight without walking any steps yet,
        // onSensorChanged may not have fired, but we still need to finalize yesterday's record.
        if (currentRaw > 0L) {
            StepDbHelper.handleDateRollover(this, currentRaw, today)
        }

        if (pendingStepResults.isNotEmpty()) {
            val callbacks = ArrayList(pendingStepResults)
            pendingStepResults.clear()
            for (cb in callbacks) {
                cb.success(mapOf(
                    "rawSteps" to currentRaw,
                    "stepDate" to today,
                    "discardedSteps" to discardedStepsToday
                ))
            }
        }
    }

    override fun onResume() {
        super.onResume()
        stepSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 5_000_000)
            try {
                sensorManager?.flush(this)
            } catch (_: Exception) {}
        }
        stepDetectorSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 5_000_000)
        }
    }

    override fun onPause() {
        super.onPause()
        // DO NOT unregister listener on pause!
        // The step sensor listener must remain active while the screen is off and
        // the phone is in the user's pocket so hardware steps continue to be tracked accurately.
    }

    override fun onDestroy() {
        try {
            validationHandler.removeCallbacks(validationRunnable)
            sensorManager?.unregisterListener(this)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    // ── UsageEvents foreground-only computation ──────────────────────────────
    /**
     * Compute per-app FOREGROUND duration accurately using UsageEvents.
     *
     * Key fixes applied:
     *   1. Only ONE app can be active in foreground at any time. When App B moves to
     *      foreground, App A's active session is closed at that exact timestamp.
     *   2. Screen-off / lock events (SCREEN_NON_INTERACTIVE, KEYGUARD_SHOWN) close the active session immediately.
     *   3. System UI, launchers, input methods, and non-launchable background services are excluded.
     *   4. All sessions belonging to the same package are cleanly aggregated into a single entry.
     */
    private fun computeForegroundUsage(startMs: Long, endMs: Long): List<Map<String, Any>> {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val events = usageStatsManager.queryEvents(startMs, endMs)
        val event = UsageEvents.Event()

        var currentForegroundPkg: String? = null
        var currentForegroundStart: Long = 0L
        val durationMap = HashMap<String, Long>()

        val blacklist = setOf(
            "com.android.systemui",
            "android",
            "com.google.android.apps.nexuslauncher",
            "com.sec.android.app.launcher",
            "com.android.launcher",
            "com.android.launcher3",
            "com.miui.home",
            "com.oppo.launcher",
            "com.oneplus.launcher",
            "com.huawei.android.launcher",
            "com.realme.launcher",
            "com.iqoo.securitycenter",
            "com.coloros.safecenter",
            "com.google.android.inputmethod.latin",
            "com.samsung.android.honeyboard",
            "com.sohu.inputmethod.sogou",
            "com.touchtype.swiftkey",
            "com.google.android.gms",
            "com.google.android.gsf",
            "com.google.android.packageinstaller",
            "com.android.packageinstaller",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller"
        )

        // Cache launchable apps verification
        val launchableCache = HashMap<String, Boolean>()
        val pm = packageManager

        fun isUserFacingApp(pkg: String): Boolean {
            if (blacklist.contains(pkg)) return false
            return launchableCache.getOrPut(pkg) {
                try {
                    // Check if package has a launcher intent OR is a non-system application
                    val hasLaunchIntent = pm.getLaunchIntentForPackage(pkg) != null
                    if (hasLaunchIntent) {
                        true
                    } else {
                        val appInfo = pm.getApplicationInfo(pkg, 0)
                        (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) == 0
                    }
                } catch (e: Exception) {
                    false
                }
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            val eventType = event.eventType
            val timestamp = event.timeStamp

            when (eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    // 1. Close previously active foreground app session
                    if (currentForegroundPkg != null && currentForegroundStart > 0L) {
                        val duration = timestamp - currentForegroundStart
                        if (duration > 0 && isUserFacingApp(currentForegroundPkg!!)) {
                            durationMap[currentForegroundPkg!!] =
                                (durationMap[currentForegroundPkg!!] ?: 0L) + duration
                        }
                    }

                    // 2. Start new foreground session if it's a user-facing app
                    if (isUserFacingApp(pkg)) {
                        currentForegroundPkg = pkg
                        currentForegroundStart = timestamp
                    } else {
                        currentForegroundPkg = null
                        currentForegroundStart = 0L
                    }
                }

                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    if (currentForegroundPkg == pkg && currentForegroundStart > 0L) {
                        val duration = timestamp - currentForegroundStart
                        if (duration > 0 && isUserFacingApp(pkg)) {
                            durationMap[pkg] = (durationMap[pkg] ?: 0L) + duration
                        }
                        currentForegroundPkg = null
                        currentForegroundStart = 0L
                    }
                }

                UsageEvents.Event.SCREEN_NON_INTERACTIVE,
                UsageEvents.Event.KEYGUARD_SHOWN -> {
                    // Screen locked / turned off — stop tracking active session immediately
                    if (currentForegroundPkg != null && currentForegroundStart > 0L) {
                        val duration = timestamp - currentForegroundStart
                        if (duration > 0 && isUserFacingApp(currentForegroundPkg!!)) {
                            durationMap[currentForegroundPkg!!] =
                                (durationMap[currentForegroundPkg!!] ?: 0L) + duration
                        }
                    }
                    currentForegroundPkg = null
                    currentForegroundStart = 0L
                }
            }
        }

        // Handle app still in foreground at query end boundary (e.g. app actively open right now)
        if (currentForegroundPkg != null && currentForegroundStart > 0L) {
            val duration = endMs - currentForegroundStart
            if (duration > 0 && isUserFacingApp(currentForegroundPkg!!)) {
                durationMap[currentForegroundPkg!!] =
                    (durationMap[currentForegroundPkg!!] ?: 0L) + duration
            }
        }

        // Filter: minimum 5 seconds of actual foreground user interaction
        // Deduplicate and sort descending by duration
        return durationMap.entries
            .filter { it.value >= 5000L } // at least 5 seconds
            .sortedByDescending { it.value }
            .map { mapOf("packageName" to it.key, "durationMs" to it.value) }
    }

    private fun hasUsagePermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    // ── App metadata & icon helpers ──────────────────────────────────────────

    private fun getSingleAppInfo(packageName: String): Map<String, String>? {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            val label = pm.getApplicationLabel(appInfo).toString()
            val drawable = pm.getApplicationIcon(appInfo)
            val iconBase64 = drawableToBase64(drawable)
            mapOf("appName" to label, "iconBase64" to iconBase64)
        } catch (e: Exception) {
            null
        }
    }

    private fun drawableToBase64(drawable: Drawable): String {
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val w = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
            val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
            val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(b)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            b
        }
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 85, outputStream)
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
    }
}
