package com.example.flutter_application_1

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener2
import android.hardware.SensorManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class DailyStepWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

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
            val stepSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, true)
                ?: sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                ?: return@withContext Result.success()

            // Fetch live hardware step count using flush + CountDownLatch
            // Events arrive on the main looper; read on this IO thread.
            val latest = AtomicLong(0L)
            val latch = CountDownLatch(1)
            val listener = object : SensorEventListener2 {
                override fun onSensorChanged(event: SensorEvent?) {
                    if (event != null && event.sensor.type == Sensor.TYPE_STEP_COUNTER) {
                        val count = event.values[0].toLong()
                        if (count > 0L) {
                            latest.set(count)
                            latch.countDown()
                        }
                    }
                }
                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                override fun onFlushCompleted(sensor: Sensor?) {
                    latch.countDown()
                }
            }

            sensorManager.registerListener(listener, stepSensor, SensorManager.SENSOR_DELAY_NORMAL, 5_000_000)
            try {
                sensorManager.flush(listener)
            } catch (_: Exception) {}

            latch.await(1000, TimeUnit.MILLISECONDS)
            sensorManager.unregisterListener(listener)
            val rawSteps = latest.get()

            // Same single source of truth as the service: feed the absolute counter value.
            // Delta-based counting makes this a no-op if the service already saw it.
            StepRepository.init(context)
            if (rawSteps > 0L) StepRepository.onCounter(rawSteps)
            StepRepository.tick(force = !StepTrackingService.isRunning)
            StepRepository.flush()

            // Bring the foreground service back if the system stopped it (allowed from a
            // worker on most versions; failures are caught inside start()).
            if (!StepTrackingService.isRunning) StepTrackingService.start(context)

            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }
}
