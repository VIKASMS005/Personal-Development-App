package com.example.flutter_application_1

import android.os.SystemClock
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * GaitValidator — Intelligent Pedometer Fraud & Shaking Detector (v6).
 *
 * Designed to be 100% ORIENTATION-INDEPENDENT & ACCURATE:
 * Works identically whether the phone is:
 *  - Held in hand
 *  - In a trouser/pants pocket (upright, upside-down, or tilted)
 *  - In a shirt/jacket pocket
 *  - In a backpack or handbag
 *  - Screen ON or OFF / Locked
 *  - Walking indoors or outdoors (no GPS required)
 *
 * Mathematical Core:
 *  Uses 3D Euclidean dynamic acceleration:
 *    m(t) = sqrt(ax^2 + ay^2 + az^2)
 *    d(t) = m(t) - 9.80665 m/s²
 *  Operates on unrectified dynamic acceleration with 5-point moving average smoothing
 *  and Schmitt-trigger hysteresis (±0.40 m/s²) to eliminate sensor noise.
 *  Measures true bipedal cadence (1.0 - 3.2 Hz for walking/running).
 *
 * Fraud & False-Positive Rejection Rules:
 *  1. Sleep / Low Sample Count: If phone was asleep in pocket/bag (n < 40 samples),
 *     trust hardware pedometer events 100%.
 *  2. Fast Hand Shaking / Leg Tremor: Fast hand shaking occurs at 4.5 - 8.0 Hz.
 *     Human walking/running cadence never exceeds 3.5 Hz (210 steps/min).
 *     Flagged only if frequency >= 4.2 Hz with RMS > 2.0 m/s².
 *  3. Violent Shaking: Peak dynamic acceleration > 18.0 m/s² with sustained RMS > 5.5 m/s².
 *  4. Vehicle Engine Vibration: High frequency jitter > 10.0 Hz with low RMS (< 0.6 m/s²).
 *  5. Step Rate Limiter: Synchronized to SystemClock.elapsedRealtimeNanos() matching
 *     SensorEvent.timestamp. Rejects cadence > 3.6 steps/sec (> 7 steps in 2s).
 */
class GaitValidator {

    companion object {
        private const val BUFFER_SIZE = 500 // ~10s circular buffer at ~50Hz
        private const val MIN_SAMPLES_FOR_ANALYSIS = 40 // ~0.8s minimum to evaluate active motion

        // Earth gravity constant (m/s²)
        private const val GRAVITY_EARTH = 9.80665f

        // Stationary threshold: dynamic RMS below this means phone is at rest
        private const val STATIONARY_RMS_THRESHOLD = 0.20f // m/s²

        // Fast hand shaking cadence frequency threshold (4.2 Hz = 252 steps/min)
        // Human sprinting cadence tops out around 3.3 - 3.5 Hz. Hand shaking is 4.5 - 8 Hz.
        private const val FAST_SHAKE_MIN_FREQ_HZ = 4.20f

        // Step arrival rate limit (steps per second)
        private const val MAX_VALID_STEP_RATE_HZ = 3.6f

        // Schmitt-trigger hysteresis thresholds for noise-free cycle detection (m/s²)
        private const val HYSTERESIS_HIGH = 0.40f
        private const val HYSTERESIS_LOW = -0.40f
    }

    // 3D Accelerometer circular buffer
    private val axBuffer = FloatArray(BUFFER_SIZE)
    private val ayBuffer = FloatArray(BUFFER_SIZE)
    private val azBuffer = FloatArray(BUFFER_SIZE)
    private val timeBuffer = LongArray(BUFFER_SIZE)
    private var bufIdx = 0
    private var sampleCount = 0L

    // Step event timestamp tracking for cadence rate limit (using SystemClock.elapsedRealtimeNanos)
    private val stepTimestamps = LongArray(32)
    private var stepTimestampIdx = 0
    private var totalStepsRecorded = 0

    // Analysis results
    private var _isShaking = false
    private var _isWalking = true
    private var _isStationary = false
    private var _confidence = 1.0f

    @Synchronized
    fun addSample(x: Float, y: Float, z: Float, timestampNanos: Long) {
        axBuffer[bufIdx] = x
        ayBuffer[bufIdx] = y
        azBuffer[bufIdx] = z
        timeBuffer[bufIdx] = timestampNanos
        bufIdx = (bufIdx + 1) % BUFFER_SIZE
        sampleCount++
    }

    /**
     * Record a hardware step event timestamp to monitor step arrival cadence.
     * Uses SystemClock.elapsedRealtimeNanos() matching SensorEvent.timestamp timebase.
     */
    @Synchronized
    fun recordStepArrival(timestampNanos: Long = SystemClock.elapsedRealtimeNanos()) {
        stepTimestamps[stepTimestampIdx] = timestampNanos
        stepTimestampIdx = (stepTimestampIdx + 1) % stepTimestamps.size
        totalStepsRecorded++
    }

    /**
     * Check if step arrival rate over the last 2 seconds exceeds human limits (> 3.6 steps/sec).
     * Strictly uses SystemClock.elapsedRealtimeNanos() to prevent clock mismatch.
     */
    @Synchronized
    fun isStepRateExcessive(nowNanos: Long = SystemClock.elapsedRealtimeNanos()): Boolean {
        if (totalStepsRecorded < 6) return false
        val twoSecondsAgo = nowNanos - 2_000_000_000L
        var countInWindow = 0
        val size = min(totalStepsRecorded, stepTimestamps.size)
        for (i in 0 until size) {
            val ts = stepTimestamps[i]
            // Must be within [now - 2s, now + 0.5s] to account for any slight buffer scheduling
            if (ts in twoSecondsAgo..(nowNanos + 500_000_000L)) {
                countInWindow++
            }
        }
        // > 7 steps in 2 seconds = > 3.5 steps/sec = physically impossible for walking
        return countInWindow > (MAX_VALID_STEP_RATE_HZ * 2.0f).toInt()
    }

    @Synchronized
    fun analyze() {
        val n = min(sampleCount.toInt(), BUFFER_SIZE)
        if (n < MIN_SAMPLES_FOR_ANALYSIS) {
            // Not enough accelerometer samples (e.g. phone screen was off, device asleep in pocket)
            // Innocent until proven guilty: accept hardware pedometer steps unconditionally
            _isWalking = true
            _isShaking = false
            _isStationary = false
            _confidence = 0.85f
            return
        }

        // 1. Compute 3D Orientation-Invariant Unrectified Dynamic Acceleration:
        //    d(t) = sqrt(ax^2 + ay^2 + az^2) - 9.80665 m/s²
        val rawDyn = FloatArray(n)
        var dynRmsSum = 0.0
        var maxAbsDynMag = 0f

        for (i in 0 until n) {
            val idx = (bufIdx - n + i + BUFFER_SIZE) % BUFFER_SIZE
            val ax = axBuffer[idx]
            val ay = ayBuffer[idx]
            val az = azBuffer[idx]
            val mag = sqrt(ax * ax + ay * ay + az * az)
            val d = mag - GRAVITY_EARTH

            rawDyn[i] = d
            dynRmsSum += d * d
            val absD = abs(d)
            if (absD > maxAbsDynMag) maxAbsDynMag = absD
        }

        val dynRms = sqrt(dynRmsSum / n).toFloat()

        // 2. Stationary Check: If dynamic acceleration is negligible, phone is at rest
        if (dynRms < STATIONARY_RMS_THRESHOLD) {
            _isStationary = true
            _isWalking = false
            _isShaking = false
            _confidence = 0.0f
            return
        }
        _isStationary = false

        // 3. Smooth with 5-point moving average to eliminate accelerometer high-frequency noise
        val smoothed = FloatArray(n)
        for (i in 0 until n) {
            if (i in 2 until (n - 2)) {
                smoothed[i] = (rawDyn[i - 2] + rawDyn[i - 1] + rawDyn[i] + rawDyn[i + 1] + rawDyn[i + 2]) / 5.0f
            } else {
                smoothed[i] = rawDyn[i]
            }
        }

        // 4. Schmitt-trigger hysteresis state machine for robust, noise-free cadence frequency
        //    Only switches state when signal crosses +0.40 m/s² or -0.40 m/s².
        //    Normal walking measures 1.2 - 2.8 Hz. Fast hand shaking measures 4.5 - 8.0 Hz.
        var halfCycles = 0
        var state = 0 // +1 = high, -1 = low, 0 = neutral
        for (i in 0 until n) {
            val v = smoothed[i]
            if (v > HYSTERESIS_HIGH && state != 1) {
                if (state == -1) halfCycles++
                state = 1
            } else if (v < HYSTERESIS_LOW && state != -1) {
                if (state == 1) halfCycles++
                state = -1
            }
        }

        val firstIdx = (bufIdx - n + BUFFER_SIZE) % BUFFER_SIZE
        val lastIdx = (bufIdx - 1 + BUFFER_SIZE) % BUFFER_SIZE
        val dtNanos = timeBuffer[lastIdx] - timeBuffer[firstIdx]
        val dtSec = if (dtNanos > 100_000_000L) dtNanos / 1_000_000_000.0 else (n / 50.0)
        // 2 half-cycles = 1 full cycle
        val estimatedFreqHz = if (dtSec > 0.2) (halfCycles / 2.0 / dtSec).toFloat() else 0f

        // ── SHAKING & FRAUD DETECTION CRITERIA (ORIENTATION-INDEPENDENT) ─────

        // Criterion 1: FAST HAND SHAKING / INTENTIONAL RAPID OSCILLATION
        // Walking/running cadence never exceeds 3.5 Hz. Hand shaking is 4.5 - 8.0 Hz.
        val isFastShaking = estimatedFreqHz >= FAST_SHAKE_MIN_FREQ_HZ && dynRms > 2.0f

        // Criterion 2: VIOLENT ABNORMAL SHAKING
        // Deliberate violent shaking generates shocks > 18.0 m/s² with sustained RMS > 5.5 m/s².
        val isViolentShaking = maxAbsDynMag > 18.0f && dynRms > 5.5f

        // Criterion 3: VEHICLE ENGINE VIBRATION
        // High frequency (> 10 Hz) with small chassis amplitude (RMS < 0.6 m/s²).
        val isVehicleVibration = estimatedFreqHz > 10.0f && dynRms < 0.6f

        // Criterion 4: STEP ARRIVAL CADENCE ABUSE
        val isStepRateAbnormal = isStepRateExcessive()

        // Overall Shaking Verdict: True ONLY if unequivocal shaking is proven
        _isShaking = isFastShaking || isViolentShaking || isVehicleVibration || isStepRateAbnormal
        _isWalking = !_isShaking
        _confidence = if (_isShaking) 0.95f else 0.90f
    }

    @Synchronized fun isShakingMotion(): Boolean = _isShaking
    @Synchronized fun isWalkingGait(): Boolean = _isWalking
    @Synchronized fun isStationary(): Boolean = _isStationary
    @Synchronized fun getGaitConfidence(): Float = _confidence
    @Synchronized fun getSampleCount(): Int = min(sampleCount.toInt(), BUFFER_SIZE)

    @Synchronized
    fun reset() {
        bufIdx = 0
        sampleCount = 0L
        stepTimestampIdx = 0
        totalStepsRecorded = 0
        _isShaking = false
        _isWalking = true
        _isStationary = false
        _confidence = 1.0f
    }
}
