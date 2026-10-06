package com.example.flutter_application_1

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.math.sqrt

/**
 * GaitValidator (v7) — decides whether steps reported by the hardware pedometer during a
 * short window really came from walking/running, using the accelerometer.
 *
 * Why it was rewritten (root causes in v6):
 *  - Every step was recorded twice (step detector + step counter) in the step-rate check,
 *    so ordinary walking (>= 1.75 steps/s) was flagged as "> 3.5 steps/s" and discarded.
 *  - Running was flagged as "violent shaking" (peaks > 18 m/s², RMS > 5.5 m/s²).
 *  - The 10 s sample buffer was never aged out, so stale samples (from before the screen
 *    turned off) decided the verdict for later steps.
 *  - Its verdict was applied retroactively to steps already shown, making the count drop.
 *
 * Approach (orientation independent — works in pocket, jacket, bag, hand):
 *  - Use only samples whose timestamps fall inside the window being judged.
 *  - Signal = |a| (magnitude), mean removed, resampled to a uniform 50 Hz grid and
 *    lightly smoothed. Magnitude does not depend on how the phone is oriented.
 *  - Walking and running are strongly *periodic* at the step rate (≈0.8–3.8 steps/s).
 *    The normalized autocorrelation finds the dominant period.
 *  - Reject when:
 *      * the phone is essentially still (nobody carried it while stepping),
 *      * the dominant rhythm is faster than any human cadence (hand shaking, leg jiggling,
 *        vibration),
 *      * the motion has no rhythm at all (random hand movements, picking up / putting down),
 *      * the reported step rate is physically impossible.
 *  - If there is not enough accelerometer data (phone asleep in a pocket/bag with the
 *    screen off) the hardware pedometer — which has its own walking filter — is trusted.
 */
class GaitValidator(private val capacity: Int = 1024) {

    enum class Reason { ACCEPTED, INSUFFICIENT_DATA_TRUSTED, STILL, TOO_FAST_SHAKING, NO_RHYTHM, IMPOSSIBLE_RATE }

    data class Verdict(
        val accepted: Long,
        val reason: Reason,
        val cadenceHz: Float = 0f,
        val periodicity: Float = 0f,
        val rms: Float = 0f,
    )

    companion object {
        const val RESAMPLE_HZ = 50.0
        /** Minimum covered span (s) of accelerometer data needed to judge a window. */
        const val MIN_SPAN_SEC = 2.0
        /** A gap longer than this inside the window means the sensor was paused. */
        const val MAX_GAP_SEC = 0.5
        /** Below this RMS of dynamic acceleration the phone is not being carried by a walker. */
        const val STILL_RMS = 0.18f
        /** Human step cadence range (steps per second). */
        const val MIN_CADENCE_HZ = 0.8
        const val MAX_CADENCE_HZ = 3.8
        /** Below this normalized autocorrelation there is no repeating gait pattern. */
        const val MIN_PERIODICITY = 0.25f
        /** Physically impossible sustained step rate (elite sprint is ~4.5–5/s). */
        const val MAX_STEP_RATE_HZ = 5.0
        /** Hardware counters often release a batch of steps they held while confirming a walk. */
        const val BATCH_ALLOWANCE_STEPS = 12L
    }

    private val xs = FloatArray(capacity)
    private val ys = FloatArray(capacity)
    private val zs = FloatArray(capacity)
    private val ts = LongArray(capacity)
    private var head = 0 // next write position
    private var size = 0

    @Synchronized
    fun addSample(x: Float, y: Float, z: Float, timestampNanos: Long) {
        xs[head] = x; ys[head] = y; zs[head] = z; ts[head] = timestampNanos
        head = (head + 1) % capacity
        if (size < capacity) size++
    }

    @Synchronized
    fun reset() {
        head = 0
        size = 0
    }

    /**
     * Judge [steps] pending steps reported between [startNanos] and [endNanos]
     * (same timebase as the sample timestamps).
     */
    @Synchronized
    fun evaluate(steps: Long, startNanos: Long, endNanos: Long): Verdict {
        if (steps <= 0L) return Verdict(0L, Reason.ACCEPTED)

        // 1. Collect samples inside the window, oldest first.
        val tList = ArrayList<Long>(size)
        val mList = ArrayList<Float>(size)
        for (i in 0 until size) {
            val idx = (head - size + i + capacity) % capacity
            val t = ts[idx]
            if (t in startNanos..endNanos) {
                tList.add(t)
                mList.add(sqrt(xs[idx] * xs[idx] + ys[idx] * ys[idx] + zs[idx] * zs[idx]))
            }
        }
        if (tList.size < 2) return Verdict(steps, Reason.INSUFFICIENT_DATA_TRUSTED)

        val spanSec = (tList.last() - tList.first()) / 1e9
        var maxGapSec = 0.0
        for (i in 1 until tList.size) maxGapSec = max(maxGapSec, (tList[i] - tList[i - 1]) / 1e9)
        if (spanSec < MIN_SPAN_SEC || maxGapSec > MAX_GAP_SEC) {
            return Verdict(steps, Reason.INSUFFICIENT_DATA_TRUSTED)
        }

        // 2. Physically impossible rate (the window can be shorter than the walk that
        //    produced a batched report, so allow for one hardware batch).
        val windowSec = max(spanSec, (endNanos - startNanos) / 1e9)
        if (steps > (MAX_STEP_RATE_HZ * windowSec).roundToLong() + BATCH_ALLOWANCE_STEPS) {
            return Verdict(0L, Reason.IMPOSSIBLE_RATE)
        }

        // 3. Resample |a| to a uniform grid, remove the mean (gravity + calibration bias).
        val signal = resample(tList, mList)
        val mean = signal.average().toFloat()
        for (i in signal.indices) signal[i] -= mean
        val smooth = movingAverage(signal, 3)
        var sq = 0.0
        for (v in smooth) sq += v * v
        val rms = sqrt(sq / smooth.size).toFloat()

        if (rms < STILL_RMS) return Verdict(0L, Reason.STILL, rms = rms)

        // 4. Dominant period via normalized autocorrelation over lags 0.08 s .. 1.3 s.
        val minLag = (0.08 * RESAMPLE_HZ).toInt()
        val maxLag = min((1.3 * RESAMPLE_HZ).toInt(), smooth.size / 2)
        if (maxLag <= minLag + 2) return Verdict(steps, Reason.INSUFFICIENT_DATA_TRUSTED, rms = rms)
        val ac = autocorrelation(smooth, maxLag)

        // Local maxima, then the strongest one; prefer the shortest lag whose peak is almost
        // as strong (the step period rather than the stride = 2 steps).
        var bestLag = -1
        var bestVal = -1f
        val peaks = ArrayList<Int>()
        for (lag in minLag + 1 until maxLag) {
            if (ac[lag] > ac[lag - 1] && ac[lag] >= ac[lag + 1] && ac[lag] > 0f) {
                peaks.add(lag)
                if (ac[lag] > bestVal) { bestVal = ac[lag]; bestLag = lag }
            }
        }
        if (bestLag < 0) return Verdict(0L, Reason.NO_RHYTHM, rms = rms)
        var stepLag = bestLag
        for (lag in peaks) {
            if (lag < stepLag && ac[lag] >= 0.8f * bestVal) { stepLag = lag; break }
        }
        val cadence = (RESAMPLE_HZ / stepLag).toFloat()
        val periodicity = ac[stepLag]

        if (cadence > MAX_CADENCE_HZ && periodicity >= MIN_PERIODICITY) {
            // The fundamental rhythm is faster than any human gait: hand shaking, leg
            // jiggling while sitting, vibration. (Its multiples also show up as peaks in the
            // gait range, which is why the *shortest* strong period is used, not any peak.)
            return Verdict(0L, Reason.TOO_FAST_SHAKING, cadence, periodicity, rms)
        }
        if (periodicity < MIN_PERIODICITY) {
            return Verdict(0L, Reason.NO_RHYTHM, cadence, periodicity, rms)
        }
        return Verdict(steps, Reason.ACCEPTED, cadence, periodicity, rms)
    }

    private fun resample(t: List<Long>, m: List<Float>): FloatArray {
        val t0 = t.first()
        val span = (t.last() - t0) / 1e9
        val n = max(2, (span * RESAMPLE_HZ).toInt() + 1)
        val out = FloatArray(n)
        var j = 0
        for (i in 0 until n) {
            val tt = t0 + (i / RESAMPLE_HZ * 1e9).toLong()
            while (j < t.size - 2 && t[j + 1] < tt) j++
            val ta = t[j]; val tb = t[j + 1]
            val frac = if (tb > ta) ((tt - ta).toDouble() / (tb - ta)).coerceIn(0.0, 1.0) else 0.0
            out[i] = (m[j] + (m[j + 1] - m[j]) * frac).toFloat()
        }
        return out
    }

    private fun movingAverage(x: FloatArray, w: Int): FloatArray {
        val out = FloatArray(x.size)
        val h = w / 2
        for (i in x.indices) {
            var s = 0f
            var c = 0
            for (k in max(0, i - h)..min(x.size - 1, i + h)) { s += x[k]; c++ }
            out[i] = s / c
        }
        return out
    }

    /** Normalized (unbiased-length) autocorrelation r(lag) in [-1, 1]. */
    private fun autocorrelation(x: FloatArray, maxLag: Int): FloatArray {
        val out = FloatArray(maxLag + 1)
        for (lag in 0..maxLag) {
            var num = 0.0
            var e1 = 0.0
            var e2 = 0.0
            for (i in 0 until x.size - lag) {
                num += x[i] * x[i + lag]
                e1 += x[i] * x[i]
                e2 += x[i + lag] * x[i + lag]
            }
            val den = sqrt(e1 * e2)
            out[lag] = if (den > 1e-9) (num / den).toFloat() else 0f
        }
        return out
    }
}
