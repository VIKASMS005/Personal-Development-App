package com.example.flutter_application_1

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Simulated-sensor tests for the step pipeline (StepCountEngine + GaitValidator).
 *
 * Pure JVM, no Android or JUnit dependency, so it runs with plain kotlinc:
 *   kotlinc StepCountEngine.kt GaitValidator.kt StepSimulationTest.kt -include-runtime -d t.jar
 *   java -cp t.jar com.example.flutter_application_1.StepSimulationTestKt
 *
 * Physical conditions (pocket, bag, cadence) are modelled as accelerometer signals; they
 * approximate, but do not replace, walking with a real phone.
 */

private var failures = 0
private var passes = 0

private fun check(name: String, ok: Boolean, detail: String = "") {
    if (ok) passes++ else failures++
    println("${if (ok) "PASS" else "FAIL"}  $name ${if (detail.isNotEmpty()) "— $detail" else ""}")
}

private const val SEC = 1_000_000_000L

/** Random fixed phone orientation: unit vector for "up" in phone coordinates. */
private fun randomUp(rnd: Random): DoubleArray {
    val th = rnd.nextDouble(0.0, PI)
    val ph = rnd.nextDouble(0.0, 2 * PI)
    return doubleArrayOf(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
}

private fun perpendicular(u: DoubleArray): DoubleArray {
    val a = if (kotlin.math.abs(u[0]) < 0.9) doubleArrayOf(1.0, 0.0, 0.0) else doubleArrayOf(0.0, 1.0, 0.0)
    val c = doubleArrayOf(u[1] * a[2] - u[2] * a[1], u[2] * a[0] - u[0] * a[2], u[0] * a[1] - u[1] * a[0])
    val n = sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2])
    return doubleArrayOf(c[0] / n, c[1] / n, c[2] / n)
}

/**
 * Feed [durationSec] of accelerometer samples to the validator. [vertical] / [horizontal]
 * give dynamic acceleration (m/s²) along the world-up axis and a horizontal axis.
 */
private fun feed(
    v: GaitValidator, rnd: Random, t0: Long, durationSec: Double,
    noise: Double, vertical: (Double) -> Double, horizontal: (Double) -> Double,
): Long {
    val up = randomUp(rnd)
    val side = perpendicular(up)
    var t = t0
    val end = t0 + (durationSec * SEC).toLong()
    while (t < end) {
        val s = (t - t0) / 1e9
        val av = 9.80665 + vertical(s)
        val ah = horizontal(s)
        val x = up[0] * av + side[0] * ah + rnd.nextDouble(-noise, noise)
        val y = up[1] * av + side[1] * ah + rnd.nextDouble(-noise, noise)
        val z = up[2] * av + side[2] * ah + rnd.nextDouble(-noise, noise)
        v.addSample(x.toFloat(), y.toFloat(), z.toFloat(), t)
        t += (rnd.nextDouble(18.0, 22.0) * 1_000_000).toLong() // ~50 Hz with jitter
    }
    return end
}

/** Gait model: one impact per step with harmonics, horizontal sway at stride rate. */
private fun gait(cadence: Double, amp: Double, impact: Double, rnd: Random): Pair<(Double) -> Double, (Double) -> Double> {
    val ph = rnd.nextDouble(0.0, 2 * PI)
    val jitter = rnd.nextDouble(0.97, 1.03)
    val f = cadence * jitter
    val vert = { s: Double ->
        val p = 2 * PI * f * s + ph
        val phase = ((f * s) % 1.0)
        amp * sin(p) + 0.4 * amp * sin(2 * p + 0.7) + impact * exp(-phase * 25.0)
    }
    val hor = { s: Double -> 0.35 * amp * sin(PI * f * s + ph) }
    return vert to hor
}

private data class Condition(val name: String, val cadence: Double, val amp: Double, val impact: Double, val noise: Double)

fun main(args: Array<String>) {
    val rnd = Random(args.firstOrNull()?.toIntOrNull() ?: 42)
    val window = 6.0 // seconds of accelerometer data the service judges (pending window + lead-in)

    // ── 1. Walking / running in different carry positions must be ACCEPTED ──────────
    val speeds = listOf(
        Condition("slow walking", 1.3, 0.9, 0.6, 0.15),
        Condition("normal walking", 1.8, 1.8, 1.5, 0.2),
        Condition("fast walking", 2.2, 2.8, 2.5, 0.25),
        Condition("jogging", 2.7, 6.0, 8.0, 0.3),
        Condition("running", 3.1, 9.0, 18.0, 0.4),
    )
    val positions = listOf("trouser pocket" to 1.3, "shirt/jacket pocket" to 0.85, "bag" to 0.5, "hand" to 0.7)

    for (sp in speeds) for ((pos, scale) in positions) {
        var accepted = 0
        val trials = 20
        for (trial in 0 until trials) {
            val v = GaitValidator()
            val (vert, hor) = gait(sp.cadence, sp.amp * scale, sp.impact * scale, rnd)
            val end = feed(v, rnd, 5 * SEC, window, sp.noise, vert, hor)
            val steps = (sp.cadence * 4).toLong() // 4 s worth of pending steps
            val verdict = v.evaluate(steps, end - (window * SEC).toLong(), end)
            if (verdict.accepted == steps) accepted++
        }
        check("${sp.name} / $pos counted", accepted >= trials - 1, "$accepted/$trials windows accepted")
    }

    // ── 2. Non-walking motion must be REJECTED ──────────────────────────────────────
    fun rejectRate(name: String, trials: Int = 20, make: (Random) -> Pair<(Double) -> Double, (Double) -> Double>, noise: Double, minRejected: Int = trials - 1) {
        var rejected = 0
        var lastReason = ""
        for (trial in 0 until trials) {
            val v = GaitValidator()
            val (vert, hor) = make(rnd)
            val end = feed(v, rnd, 5 * SEC, window, noise, vert, hor)
            val verdict = v.evaluate(8, end - (window * SEC).toLong(), end)
            if (verdict.accepted == 0L) rejected++
            lastReason = verdict.reason.name
        }
        check("$name rejected", rejected >= minRejected, "$rejected/$trials rejected (e.g. $lastReason)")
    }

    rejectRate("fast hand shaking (5–7 Hz)", make = { r ->
        val f = r.nextDouble(5.0, 7.0); val a = r.nextDouble(6.0, 15.0)
        ({ s: Double -> a * sin(2 * PI * f * s) }) to ({ s: Double -> a * 1.2 * cos(2 * PI * f * s) })
    }, noise = 0.3)
    rejectRate("leg jiggling while sitting (4.5–6.5 Hz)", make = { r ->
        val f = r.nextDouble(4.5, 6.5); val a = r.nextDouble(0.8, 2.5)
        ({ s: Double -> a * sin(2 * PI * f * s) }) to ({ s: Double -> 0.3 * a * sin(2 * PI * f * s) })
    }, noise = 0.15)
    rejectRate("random hand movements", make = { r ->
        // Random smooth wandering: sum of a few random-phase low-frequency bumps (aperiodic).
        val bumps = List(6) { Triple(r.nextDouble(0.0, 6.0), r.nextDouble(0.2, 0.8), r.nextDouble(-4.0, 4.0)) }
        ({ s: Double -> bumps.sumOf { (c, w, a) -> a * exp(-((s - c) / w).let { it * it }) } }) to
            ({ s: Double -> bumps.sumOf { (c, w, a) -> -0.7 * a * exp(-((s - c - 0.3) / w).let { it * it }) } })
    }, noise = 0.2)
    rejectRate("phone lying still / desk vibration", make = { r ->
        ({ s: Double -> 0.03 * sin(2 * PI * 30.0 * s) }) to ({ _: Double -> 0.0 })
    }, noise = 0.05)
    rejectRate("vehicle-like vibration (12–20 Hz)", make = { r ->
        val f = r.nextDouble(12.0, 20.0)
        ({ s: Double -> 0.6 * sin(2 * PI * f * s) }) to ({ s: Double -> 0.3 * sin(2 * PI * f * 1.3 * s) })
    }, noise = 0.1)

    // ── 3. Screen off / phone asleep: no accelerometer data → hardware count trusted ──
    run {
        val v = GaitValidator()
        val verdict = v.evaluate(40, 0, 10 * SEC)
        check("screen OFF / locked (no accel samples) counted", verdict.accepted == 40L, verdict.reason.name)
        // Stale samples from before the screen went off must NOT judge new steps.
        val (vert, hor) = ({ s: Double -> 10 * sin(2 * PI * 6.0 * s) }) to ({ _: Double -> 0.0 })
        feed(v, rnd, 0, 6.0, 0.2, vert, hor) // shaking at t=0..6s
        val later = v.evaluate(30, 60 * SEC, 66 * SEC) // steps a minute later, screen off
        check("old shaking samples do not discard later pocket steps", later.accepted == 30L, later.reason.name)
    }

    // ── 4. Impossible step rate ─────────────────────────────────────────────────────
    run {
        val v = GaitValidator()
        val (vert, hor) = gait(1.8, 2.0, 1.5, rnd)
        val end = feed(v, rnd, 0, 6.0, 0.2, vert, hor)
        val verdict = v.evaluate(200, end - 6 * SEC, end)
        check("200 steps in 6 s rejected", verdict.accepted == 0L, verdict.reason.name)
    }

    // ── 5. Engine: single source of truth, persistence, restarts, reboots, midnight ──
    run {
        val e = StepCountEngine(StepState("2026-10-06", 0, -1))
        e.onCounter(50_000, 0)
        check("first reading only anchors (no phantom steps)", e.state.todaySteps == 0L && e.state.pendingSteps == 0L)
        e.onCounter(50_010, 1 * SEC); e.onCounter(50_020, 2 * SEC)
        check("pending holds new steps until validated", e.state.todaySteps == 0L && e.state.pendingSteps == 20L)
        check("resolve not due before window", !e.isResolveDue(3 * SEC, 4 * SEC))
        check("resolve due after window", e.isResolveDue(5 * SEC, 4 * SEC))
        e.resolvePending(20)
        check("accepted steps committed", e.state.todaySteps == 20L)

        // Duplicate listeners / worker / flush feed the same absolute value: no double count.
        repeat(5) { e.onCounter(50_020, 6 * SEC) }
        check("duplicate readings of same counter add nothing", e.state.pendingSteps == 0L)
        e.onCounter(50_030, 7 * SEC); e.onCounter(50_030, 7 * SEC); e.onCounter(50_025, 7 * SEC)
        // A late, slightly older reading (50_025) is ignored: not a reboot, not a decrease.
        e.resolvePending(e.state.pendingSteps)
        check("late/older reading ignored, no phantom steps", e.state.todaySteps == 30L && e.state.lastCounter == 50_030L,
            "today=${e.state.todaySteps}")

        // Rejected steps never reduce what was already shown.
        val before = e.state.todaySteps
        e.onCounter(e.state.lastCounter + 15, 10 * SEC)
        e.resolvePending(0)
        check("discarding pending does not lower displayed count", e.state.todaySteps == before)

        // Service restart: persisted state reloaded, counter continued in hardware meanwhile.
        e.onCounter(e.state.lastCounter + 7, 11 * SEC) // pending at time of process death
        val saved = e.persistableState()
        val restarted = StepCountEngine(saved)
        restarted.onCounter(e.state.lastCounter + 100, 0) // 100 steps walked while service was dead
        restarted.resolvePending(restarted.state.pendingSteps)
        check("service restart keeps count and recovers pending + offline steps",
            restarted.state.todaySteps == before + 107, "today=${restarted.state.todaySteps}, expected ${before + 107}")

        // Reboot: hardware counter restarts near 0.
        val beforeReboot = restarted.state.todaySteps
        restarted.onCounter(12, 0)
        restarted.resolvePending(restarted.state.pendingSteps)
        check("reboot never lowers count; steps since boot added",
            restarted.state.todaySteps == beforeReboot + 12, "today=${restarted.state.todaySteps}")
        restarted.onCounter(40, 1 * SEC); restarted.resolvePending(restarted.state.pendingSteps)
        check("counting continues after reboot", restarted.state.todaySteps == beforeReboot + 40)

        // Midnight.
        restarted.onCounter(45, 2 * SEC)
        val day = restarted.rollTo("2026-10-07")
        check("midnight finalises yesterday incl. pending", day?.steps == beforeReboot + 45, "$day")
        check("new day starts at 0", restarted.state.todaySteps == 0L && restarted.state.date == "2026-10-07")
        restarted.onCounter(60, 3 * SEC); restarted.resolvePending(15)
        check("new day counts from counter delta", restarted.state.todaySteps == 15L)
        check("same-day rollTo is a no-op", restarted.rollTo("2026-10-07") == null)

        // Manual steps.
        restarted.addManual(500)
        check("manual steps added", restarted.state.todaySteps == 515L)
        restarted.raiseTodayTo(100)
        check("raiseTodayTo never lowers", restarted.state.todaySteps == 515L)
    }

    println()
    println("Total: $passes passed, $failures failed")
    if (failures > 0) kotlin.system.exitProcess(1)
}
