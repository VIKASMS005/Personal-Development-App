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
import android.hardware.SensorManager
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// FlutterFragmentActivity is required by the Health Connect (health) plugin's permission flow.
class MainActivity : FlutterFragmentActivity() {
    private val TAG = "GrowMainActivity"
    private val CHANNEL = "com.grow.app/settings"
    private val PREFS_NAME = "grow_step_prefs"

    // MainActivity no longer listens to step sensors or computes steps. It only reads
    // StepRepository (the single source of truth) and forwards its updates to Flutter.
    private var methodChannel: MethodChannel? = null
    private val stepListener = StepRepository.Listener { snapshot ->
        methodChannel?.invokeMethod("onStepsChanged", snapshotToMap(snapshot))
    }

    private fun snapshotToMap(s: StepRepository.Snapshot): Map<String, Any> =
        mapOf("steps" to s.steps, "stepDate" to s.date, "goal" to s.goal)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        StepRepository.init(this)

        // Schedule background step synchronization & midnight roll-over snapshots
        StepBackgroundManager.schedulePeriodicSync(this)
        StepBackgroundManager.scheduleMidnightAlarm(this)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        StepRepository.removeListener(stepListener)
        StepRepository.addListener(stepListener)
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

                    // ── Step Counter: read-only access to StepRepository ─────────
                    "isStepSensorAvailable" -> {
                        val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
                        val available = sm?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null ||
                            sm?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null
                        result.success(available)
                    }
                    "startStepTrackingService", "reinitStepSensor" -> {
                        // Idempotent: Android keeps a single service instance, and the
                        // service registers its sensors only once.
                        StepTrackingService.start(this)
                        StepTrackingService.requestFlush(this)
                        result.success(true)
                    }
                    "getTodaySteps", "forceRefreshSteps" -> {
                        StepRepository.tick()
                        if (call.method == "forceRefreshSteps") StepTrackingService.requestFlush(this)
                        result.success(snapshotToMap(StepRepository.snapshot()))
                    }
                    "addManualSteps" -> {
                        val steps = (call.argument<Number>("steps"))?.toLong() ?: 0L
                        result.success(snapshotToMap(StepRepository.addManualSteps(steps)))
                    }
                    "setCurrentUid" -> {
                        val uid = call.argument<String>("uid") ?: "local_user"
                        StepRepository.setCurrentUid(uid)
                        result.success(null)
                    }
                    "setStepGoal" -> {
                        val goal = (call.argument<Number>("goal"))?.toInt() ?: 6000
                        StepRepository.setGoal(goal)
                        result.success(null)
                    }
                    "getStepGoal" -> {
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        result.success(prefs.getInt("grow_daily_step_goal", 6000))
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

    override fun onResume() {
        super.onResume()
        // Validate any pending steps and pull fresh batched sensor events for the UI.
        StepRepository.tick()
        StepTrackingService.requestFlush(this)
    }

    override fun onDestroy() {
        StepRepository.removeListener(stepListener)
        methodChannel = null
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
