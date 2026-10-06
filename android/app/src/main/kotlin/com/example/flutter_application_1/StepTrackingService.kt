package com.example.flutter_application_1

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener2
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * StepTrackingService — Foreground service for continuous step tracking with
 * orientation-independent gait validation (v5).
 *
 * Architecture:
 *   1. Hardware Sensor Registration:
 *      - TYPE_STEP_COUNTER (primary source of cumulative hardware steps).
 *      - TYPE_STEP_DETECTOR (per-step trigger, cadence tracking, and fallback).
 *   2. TYPE_ACCELEROMETER feeds GaitValidator for 3D dynamic magnitude analysis.
 *   3. Position Independence:
 *      - Works in trouser pocket, jacket, hand, or backpack.
 *      - Does not rely on specific axes or vertical/horizontal orientation.
 *      - Trust-first: If phone was asleep in pocket/bag (few accelerometer samples),
 *        steps from hardware counter are accepted 100%.
 *   4. Fast shaking, violent shaking, and vehicle vibration are rejected cleanly.
 */
class StepTrackingService : Service(), SensorEventListener2 {
    companion object {
        private const val TAG = "StepTrackingService"
        private const val CHANNEL_ID = "grow_step_progress"
        private const val NOTIFICATION_ID = 4101
        private const val PREFS_NAME = "grow_step_prefs"
        private const val KEY_RAW_STEPS = "grow_raw_steps"
        private const val ACTION_MIDNIGHT = "com.example.flutter_application_1.STEP_MIDNIGHT"

        // Validation runs periodically every 10 seconds
        private const val VALIDATION_INTERVAL_MS = 10_000L

        // Storage keys for validation state
        private const val KEY_VALIDATED_OFFSET = "grow_validated_offset_"
        private const val KEY_DISCARDED_STEPS = "grow_discarded_steps_"

        fun start(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
            ) return
            val intent = Intent(context, StepTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun startAtMidnight(context: Context) {
            val intent = Intent(context, StepTrackingService::class.java).apply { action = ACTION_MIDNIGHT }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }
    }

    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var stepDetectorSensor: Sensor? = null
    private var accelSensor: Sensor? = null

    // Orientation-independent gait validation engine
    private val gaitValidator = GaitValidator()

    // Quarantine: raw step counter value at last validation checkpoint
    private var lastValidatedRaw = 0L
    // Total steps discarded today (false positives)
    private var discardedStepsToday = 0L
    // The last raw step counter value seen
    private var lastSeenRaw = 0L
    private var lastHardwareCounterRaw = 0L
    private var detectorStepsSinceCounter = 0L
    // Whether we've received at least one step event
    private var hasReceivedStepEvent = false

    // Fallback step accumulation when TYPE_STEP_COUNTER is absent
    private var fallbackAccumulatedSteps = 0L

    // Periodic validation handler
    private val handler = Handler(Looper.getMainLooper())
    private val validationRunnable = object : Runnable {
        override fun run() {
            performValidation()
            handler.postDelayed(this, VALIDATION_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForegroundCompat(buildNotification(0L, 0))

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager

        // 1. Register TYPE_STEP_COUNTER (primary hardware step counter)
        stepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, true)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        stepCounterSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 1_000_000)
        }

        // 2. Register TYPE_STEP_DETECTOR (step cadence & real-time counter)
        stepDetectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR, true)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        stepDetectorSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 1_000_000)
        }

        // 3. Register TYPE_ACCELEROMETER for gait validation (~50Hz)
        accelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }

        // 4. Load persisted validation state for today
        loadValidationState()

        // 5. Start periodic validation timer
        handler.postDelayed(validationRunnable, VALIDATION_INTERVAL_MS)

        Log.d(TAG, "StepTrackingService created. Counter: ${stepCounterSensor != null}, Detector: ${stepDetectorSensor != null}, Accel: ${accelSensor != null}")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_MIDNIGHT) {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getLong(KEY_RAW_STEPS, 0L)
            if (raw > 0L) StepDbHelper.handleDateRollover(this, raw, StepDbHelper.getLocalTodayString())

            // Reset validation state for new day
            resetValidationStateForNewDay()
        }
        return START_STICKY
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        when (event.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> handleStepCounterEvent(event)
            Sensor.TYPE_STEP_DETECTOR -> handleStepDetectorEvent(event)
            Sensor.TYPE_ACCELEROMETER -> handleAccelerometerEvent(event)
        }
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
        } else if (lastSeenRaw > 0L) {
            lastSeenRaw + detectorStepsSinceCounter
        } else {
            detectorStepsSinceCounter
        }
        dispatchServiceStepUpdate(effectiveRaw)
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
        dispatchServiceStepUpdate(effectiveRaw)
    }

    /**
     * Common step update handler for foreground service: records raw steps,
     * checks reboots, updates notifications.
     */
    private fun dispatchServiceStepUpdate(raw: Long) {
        if (raw <= 0L) return

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val previous = prefs.getLong(KEY_RAW_STEPS, 0L)
        val today = StepDbHelper.getLocalTodayString()

        prefs.edit().putLong(KEY_RAW_STEPS, raw).apply()
        lastSeenRaw = raw

        if (!hasReceivedStepEvent) {
            hasReceivedStepEvent = true
            if (lastValidatedRaw == 0L) {
                lastValidatedRaw = raw
            }
        }

        // Handle hardware counter reset (device reboot)
        if (previous > 0L && raw < previous) {
            StepDbHelper.handleDateRollover(this, raw, today)
            lastValidatedRaw = raw
            discardedStepsToday = 0L
            saveValidationState()
            updateNotification(0L, 0)
            return
        }

        // Handle calendar date rollover
        StepDbHelper.handleDateRollover(this, raw, today)

        // Update notification with current validated count
        val baseline = prefs.getLong("grow_baseline_$today", raw)
        if (raw >= baseline) {
            val totalRawDelta = raw - baseline
            val currentDiscarded = prefs.getLong(KEY_DISCARDED_STEPS + today, discardedStepsToday)
            discardedStepsToday = currentDiscarded
            val validatedSteps = maxOf(0L, totalRawDelta - currentDiscarded)
            val rebootOffset = prefs.getLong("grow_pre_reboot_offset_$today", 0L)
            val displaySteps = maxOf(0L, validatedSteps + rebootOffset)
            val goal = prefs.getInt("grow_daily_step_goal", 6000)
            updateNotification(displaySteps, goal)
        }
    }

    /**
     * Handle TYPE_ACCELEROMETER events.
     * Feeds 3D data to GaitValidator.
     */
    private fun handleAccelerometerEvent(event: SensorEvent) {
        gaitValidator.addSample(event.values[0], event.values[1], event.values[2], event.timestamp)
    }

    /**
     * Periodic validation: Analyze gait dynamics.
     * Promotes genuine walking steps and discards active shaking.
     */
    private fun performValidation() {
        if (!hasReceivedStepEvent || lastSeenRaw == 0L) return

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val today = StepDbHelper.getLocalTodayString()
        val uid = prefs.getString("grow_current_uid", "local_user") ?: "local_user"
        val baseline = prefs.getLong("grow_baseline_$today", lastSeenRaw)

        // Sync with SharedPreferences (which may be updated by MainActivity)
        val savedValidatedRaw = prefs.getLong(KEY_VALIDATED_OFFSET + today, 0L)
        if (savedValidatedRaw > 0L) {
            lastValidatedRaw = maxOf(lastValidatedRaw, savedValidatedRaw)
        }
        discardedStepsToday = prefs.getLong(KEY_DISCARDED_STEPS + today, 0L)

        val rawDeltaSinceLastValidation = lastSeenRaw - lastValidatedRaw
        if (rawDeltaSinceLastValidation <= 0) {
            return
        }

        // Run orientation-independent analysis
        gaitValidator.analyze()

        if (gaitValidator.isShakingMotion()) {
            // Active phone shaking or vehicle vibration detected
            discardedStepsToday += rawDeltaSinceLastValidation
            lastValidatedRaw = lastSeenRaw
            Log.d(TAG, "GaitValidator: DISCARDED $rawDeltaSinceLastValidation steps as invalid (discarded_today=$discardedStepsToday)")
        } else {
            // Valid walking (in pocket, bag, hand, etc.)
            lastValidatedRaw = lastSeenRaw
            Log.d(TAG, "GaitValidator: ACCEPTED $rawDeltaSinceLastValidation steps (genuine walking)")
        }

        saveValidationState()

        // Write validated steps to SQLite
        if (lastSeenRaw >= baseline) {
            val totalRawDelta = lastSeenRaw - baseline
            val validatedSteps = maxOf(0L, totalRawDelta - discardedStepsToday)
            StepDbHelper.writeStepRecord(this, uid, today, validatedSteps)

            val goal = prefs.getInt("grow_daily_step_goal", 6000)
            val rebootOffset = prefs.getLong("grow_pre_reboot_offset_$today", 0L)
            val displaySteps = maxOf(0L, validatedSteps + rebootOffset)
            updateNotification(displaySteps, goal)
        }
    }

    private fun loadValidationState() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val today = StepDbHelper.getLocalTodayString()
        val cleanupDone = prefs.getBoolean("grow_cleanup_v6_done", false)
        if (!cleanupDone) {
            // Clear any bogus discarded steps accumulated by previous buggy validator
            prefs.edit()
                .putLong(KEY_DISCARDED_STEPS + today, 0L)
                .putLong(KEY_VALIDATED_OFFSET + today, 0L)
                .putBoolean("grow_cleanup_v6_done", true)
                .apply()
            discardedStepsToday = 0L
            lastValidatedRaw = 0L
        } else {
            discardedStepsToday = prefs.getLong(KEY_DISCARDED_STEPS + today, 0L)
            lastValidatedRaw = prefs.getLong(KEY_VALIDATED_OFFSET + today, 0L)
        }
    }

    private fun saveValidationState() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val today = StepDbHelper.getLocalTodayString()
        prefs.edit()
            .putLong(KEY_DISCARDED_STEPS + today, discardedStepsToday)
            .putLong(KEY_VALIDATED_OFFSET + today, lastValidatedRaw)
            .apply()
    }

    private fun resetValidationStateForNewDay() {
        discardedStepsToday = 0L
        lastValidatedRaw = lastSeenRaw
        gaitValidator.reset()
        saveValidationState()
    }

    private fun updateNotification(steps: Long, goal: Int) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val effectiveGoal = if (goal > 0) goal else prefs.getInt("grow_daily_step_goal", 6000)
        val progress = if (effectiveGoal > 0) ((steps * 100L) / effectiveGoal).coerceIn(0L, 100L).toInt() else 0
        getSystemService(NotificationManager::class.java).notify(
            NOTIFICATION_ID,
            buildNotification(steps, effectiveGoal, progress)
        )
    }

    private fun drawProgressRing(progress: Int, size: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val strokeWidth = size * 0.11f
        val radius = (size / 2f) - (strokeWidth / 2f) - 2f
        val cx = size / 2f
        val cy = size / 2f

        // 1. Background circle track (dark teal)
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            color = Color.rgb(27, 45, 42) // #1B2D2A
        }
        canvas.drawCircle(cx, cy, radius, trackPaint)

        // 2. Active glowing progress arc (vibrant teal #2DD4BF)
        val sweepAngle = (progress.coerceIn(0, 100) * 3.6f)
        if (sweepAngle > 0f) {
            val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                strokeCap = Paint.Cap.ROUND
                color = Color.rgb(45, 212, 191) // #2DD4BF
            }
            val oval = RectF(cx - radius, cy - radius, cx + radius, cy + radius)
            canvas.drawArc(oval, -90f, sweepAngle, false, progressPaint)
        }

        // 3. Centered percentage text (bold white, e.g. "74%")
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = size * 0.28f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val text = "$progress%"
        val textBounds = Rect()
        textPaint.getTextBounds(text, 0, text.length, textBounds)
        val textY = cy + (textBounds.height() / 2f) - textBounds.bottom
        canvas.drawText(text, cx, textY, textPaint)

        return bitmap
    }

    private fun buildNotification(steps: Long, goal: Int = 0, progress: Int = 0): Notification {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val effectiveGoal = if (goal > 0) goal else prefs.getInt("grow_daily_step_goal", 6000)
        val effectiveProgress = if (effectiveGoal > 0) ((steps * 100L) / effectiveGoal).coerceIn(0L, 100L).toInt() else progress

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(this, 4102, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        val distanceKm = (steps * 0.762) / 1000.0
        val calories = (steps * 0.04).toInt()
        val distanceText = if (distanceKm >= 10.0) "%.1f km".format(java.util.Locale.US, distanceKm) else "%.2f km".format(java.util.Locale.US, distanceKm)

        val stepsText = if (steps > 0L) {
            "%,d steps".format(java.util.Locale.US, steps)
        } else {
            "0 steps"
        }

        val detailsText = if (steps > 0L) {
            "$distanceText • $calories kcal • Goal: %,d".format(java.util.Locale.US, effectiveGoal)
        } else {
            "Goal: %,d steps".format(java.util.Locale.US, effectiveGoal)
        }

        val ringBitmapCollapsed = drawProgressRing(effectiveProgress, 140)
        val ringBitmapExpanded = drawProgressRing(effectiveProgress, 180)

        val customView = RemoteViews(packageName, R.layout.notification_step_tracking).apply {
            setTextViewText(R.id.notif_step_count, stepsText)
            setTextViewText(R.id.notif_step_details, detailsText)
            setImageViewBitmap(R.id.notif_progress_ring, ringBitmapCollapsed)
        }

        val customBigView = RemoteViews(packageName, R.layout.notification_step_tracking_expanded).apply {
            setTextViewText(R.id.notif_step_count, stepsText)
            setTextViewText(R.id.notif_step_details, detailsText)
            setImageViewBitmap(R.id.notif_progress_ring, ringBitmapExpanded)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_sprout_small)
            .setColor(Color.rgb(45, 212, 191))
            .setCustomContentView(customView)
            .setCustomBigContentView(customBigView)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Daily Step Counter", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Live step count and daily goal progress"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
            )
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    override fun onFlushCompleted(sensor: Sensor?) = Unit
    override fun onDestroy() {
        handler.removeCallbacks(validationRunnable)
        sensorManager?.unregisterListener(this)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}