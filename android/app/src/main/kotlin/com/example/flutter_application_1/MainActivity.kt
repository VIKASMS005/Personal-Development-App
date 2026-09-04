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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity(), SensorEventListener2 {
    private val CHANNEL = "com.grow.app/settings"
    private val PREFS_NAME = "grow_step_prefs"
    private val KEY_RAW_STEPS = "grow_raw_steps"
    private val KEY_STEP_DATE = "grow_step_date"
    private val KEY_BASELINE_PREFIX = "grow_baseline_"
    private val KEY_CURRENT_UID = "grow_current_uid"

    private var sensorManager: SensorManager? = null
    private var stepSensor: Sensor? = null
    private var lastRawStepCount: Long = 0L
    private var methodChannel: MethodChannel? = null
    private val pendingStepResults = mutableListOf<MethodChannel.Result>()

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
                                    result.success(mapOf("rawSteps" to currentRaw, "stepDate" to today))
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
                            result.success(mapOf("rawSteps" to effectiveRaw, "stepDate" to today))
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
                                result.success(mapOf("rawSteps" to finalRaw, "stepDate" to today))
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

    // ── Silent Hardware Step Sensor ──────────────────────────────────────────
    private fun initStepSensor() {
        try {
            sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            // Request the hardware wake-up step sensor so hardware FIFO interrupts wake the AP during deep sleep
            val wakeUpSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, true)
            stepSensor = wakeUpSensor ?: sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

            // Pre-populate lastRawStepCount from storage so startup is instant
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
            if (savedRaw > 0L) {
                lastRawStepCount = savedRaw
            }

            stepSensor?.let {
                // Register with 5s max report latency to allow hardware FIFO batching during deep sleep
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 5_000_000)
            }
        } catch (e: Exception) {
            // Ignore if sensor not available
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || event.sensor.type != Sensor.TYPE_STEP_COUNTER) return

        val rawSteps = event.values[0].toLong()
        if (rawSteps <= 0L) return
        lastRawStepCount = rawSteps
        val today = StepDbHelper.getLocalTodayString()

        // Check and process day rollover if calendar day changed
        StepDbHelper.handleDateRollover(this, rawSteps, today)

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(KEY_RAW_STEPS, rawSteps)
            .putString(KEY_STEP_DATE, today)
            .apply()

        // Save today's steps to SQLite during batch callbacks so counts are preserved even if reclaimed
        val todayBaseline = prefs.getLong(KEY_BASELINE_PREFIX + today, -1L)
        if (todayBaseline >= 0L && rawSteps >= todayBaseline) {
            val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"
            val todaySteps = rawSteps - todayBaseline
            StepDbHelper.writeStepRecord(this, uid, today, todaySteps)
        }

        // Complete any pending getAccumulatedSteps calls with fresh hardware count
        if (pendingStepResults.isNotEmpty()) {
            val callbacks = ArrayList(pendingStepResults)
            pendingStepResults.clear()
            for (cb in callbacks) {
                cb.success(mapOf("rawSteps" to rawSteps, "stepDate" to today))
            }
        }

        // Push real-time hardware step event to Flutter
        runOnUiThread {
            methodChannel?.invokeMethod("onRawStepsChanged", mapOf("rawSteps" to rawSteps, "stepDate" to today))
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onFlushCompleted(sensor: Sensor?) {
        if (sensor?.type != Sensor.TYPE_STEP_COUNTER) return

        val today = StepDbHelper.getLocalTodayString()
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedRaw = prefs.getLong(KEY_RAW_STEPS, 0L)
        val currentRaw = if (lastRawStepCount > 0L) lastRawStepCount else savedRaw

        if (pendingStepResults.isNotEmpty()) {
            val callbacks = ArrayList(pendingStepResults)
            pendingStepResults.clear()
            for (cb in callbacks) {
                cb.success(mapOf("rawSteps" to currentRaw, "stepDate" to today))
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
    }

    override fun onPause() {
        super.onPause()
        // DO NOT unregister listener on pause!
        // The step sensor listener must remain active while the screen is off and
        // the phone is in the user's pocket so hardware steps continue to be tracked accurately.
    }

    override fun onDestroy() {
        try {
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
