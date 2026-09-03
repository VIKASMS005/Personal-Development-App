package com.example.flutter_application_1

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class DailyStepWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    companion object {
        private const val PREFS_NAME = "grow_step_prefs"
        private const val KEY_RAW_STEPS = "grow_raw_steps"
        private const val KEY_STEP_DATE = "grow_step_date"
        private const val KEY_BASELINE_PREFIX = "grow_baseline_"
        private const val KEY_CURRENT_UID = "grow_current_uid"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            // Check permission on Android 10+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION)
                    != PackageManager.PERMISSION_GRANTED) {
                    return@withContext Result.success()
                }
            }

            val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
                ?: return@withContext Result.success()
            val stepSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                ?: return@withContext Result.success()

            // Fetch live hardware step count using flush + CountDownLatch
            var rawSteps = 0L
            val latch = CountDownLatch(1)
            val listener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent?) {
                    if (event != null && event.sensor.type == Sensor.TYPE_STEP_COUNTER) {
                        rawSteps = event.values[0].toLong()
                        latch.countDown()
                    }
                }
                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }

            sensorManager.registerListener(listener, stepSensor, SensorManager.SENSOR_DELAY_NORMAL)
            try {
                sensorManager.flush(listener)
            } catch (_: Exception) {}

            latch.await(1000, TimeUnit.MILLISECONDS)
            sensorManager.unregisterListener(listener)

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // If sensor timed out, fall back to last recorded raw steps
            if (rawSteps <= 0L) {
                rawSteps = prefs.getLong(KEY_RAW_STEPS, 0L)
            }
            if (rawSteps <= 0L) {
                return@withContext Result.success()
            }

            val today = StepDbHelper.getLocalTodayString()
            val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"

            // Check and process day rollover if midnight occurred
            StepDbHelper.handleDateRollover(context, rawSteps, today)

            // Calculate steps for today
            val todayBaseline = prefs.getLong(KEY_BASELINE_PREFIX + today, rawSteps)
            val todaySteps = if (rawSteps >= todayBaseline) (rawSteps - todayBaseline) else 0L
            StepDbHelper.writeStepRecord(context, uid, today, todaySteps)

            Result.success()
        } catch (e: Exception) {
            Result.success()
        }
    }
}
