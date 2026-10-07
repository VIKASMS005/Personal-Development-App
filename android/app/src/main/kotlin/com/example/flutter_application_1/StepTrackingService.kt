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
 * StepTrackingService — the ONLY component that listens to step sensors.
 *
 *   TYPE_STEP_COUNTER (wake-up)  ──► StepRepository.onCounter      (primary source)
 *   TYPE_STEP_DETECTOR           ──► StepRepository.onDetectorStep (only if no counter)
 *   TYPE_ACCELEROMETER           ──► StepRepository.onAccelerometer (gait validation)
 *
 * It holds no step arithmetic and no step state of its own: the foreground notification
 * simply renders StepRepository's snapshot, which is the same value the app shows.
 *
 * Android creates at most one instance of a Service, and sensors are registered once in
 * onCreate (and unregistered in onDestroy), so repeated start requests cannot create
 * duplicate listeners. Because the step counter is cumulative and StepRepository counts
 * deltas, even a duplicate reading cannot add steps twice.
 */
class StepTrackingService : Service(), SensorEventListener2 {
    companion object {
        private const val TAG = "StepTrackingService"
        private const val CHANNEL_ID = "grow_step_progress"
        private const val NOTIFICATION_ID = 4101
        private const val ACTION_MIDNIGHT = "com.example.flutter_application_1.STEP_MIDNIGHT"
        private const val ACTION_FLUSH = "com.example.flutter_application_1.STEP_FLUSH"

        /** How often pending steps are checked for validation while the CPU is awake. */
        private const val TICK_INTERVAL_MS = 500L

        @Volatile
        var isRunning = false
            private set

        fun start(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
            ) return
            startWithAction(context, null)
        }

        fun startAtMidnight(context: Context) = startWithAction(context, ACTION_MIDNIGHT)

        /** Ask the running service to flush batched sensor events (fresh value for the UI). */
        fun requestFlush(context: Context) {
            if (isRunning) startWithAction(context, ACTION_FLUSH)
        }

        private fun startWithAction(context: Context, action: String?) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED
            ) return
            val intent = Intent(context, StepTrackingService::class.java).apply { this.action = action }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (e: Exception) {
                // e.g. ForegroundServiceStartNotAllowedException from the background on Android 12+.
                Log.w(TAG, "Could not start step service: ${e.message}")
            }
        }
    }

    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var stepDetectorSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var sensorsRegistered = false

    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() {
            StepRepository.tick()
            handler.postDelayed(this, TICK_INTERVAL_MS)
        }
    }

    private val repositoryListener = StepRepository.Listener { snapshot ->
        updateNotification(snapshot.steps, snapshot.goal)
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        StepRepository.init(this)
        createNotificationChannel()
        val initial = StepRepository.snapshot()
        startForegroundCompat(buildNotification(initial.steps, initial.goal))

        registerSensorsOnce()
        StepRepository.addListener(repositoryListener)
        handler.postDelayed(tickRunnable, TICK_INTERVAL_MS)

        Log.d(TAG, "StepTrackingService created. Counter: ${stepCounterSensor != null}, Detector: ${stepDetectorSensor != null}, Accel: ${accelSensor != null}")
    }

    private fun registerSensorsOnce() {
        if (sensorsRegistered) return
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager = sm

        // Primary: hardware step counter (wake-up variant so batched steps wake the CPU
        // while the screen is off / phone is locked).
        stepCounterSensor = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, true)
            ?: sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        // maxReportLatency 0: report each step as it happens instead of batching for up to 1 s.
        stepCounterSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST, 0) }

        // Fallback only: the step detector is NOT combined with the counter any more
        // (doing so double counted and let rejected detector steps through).
        if (stepCounterSensor == null) {
            stepDetectorSensor = sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR, true)
                ?: sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
            stepDetectorSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL, 1_000_000) }
        }

        // Accelerometer (~50 Hz) for gait validation.
        accelSensor = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        accelSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }

        sensorsRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_MIDNIGHT -> StepRepository.tick(force = true) // rolls the day over if needed
            ACTION_FLUSH -> {}
        }
        try { sensorManager?.flush(this) } catch (_: Exception) {}
        // Every startForegroundService() call must be answered with startForeground().
        val s = StepRepository.snapshot()
        startForegroundCompat(buildNotification(s.steps, s.goal))
        return START_STICKY
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        when (event.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> StepRepository.onCounter(event.values[0].toLong())
            Sensor.TYPE_STEP_DETECTOR -> StepRepository.onDetectorStep()
            Sensor.TYPE_ACCELEROMETER ->
                StepRepository.onAccelerometer(event.values[0], event.values[1], event.values[2], event.timestamp)
        }
    }

    private fun updateNotification(steps: Long, goal: Int) {
        getSystemService(NotificationManager::class.java).notify(
            NOTIFICATION_ID,
            buildNotification(steps, goal)
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
        val prefs = getSharedPreferences("grow_step_prefs", Context.MODE_PRIVATE)
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
        handler.removeCallbacks(tickRunnable)
        StepRepository.removeListener(repositoryListener)
        sensorManager?.unregisterListener(this)
        sensorsRegistered = false
        StepRepository.flush()
        isRunning = false
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
