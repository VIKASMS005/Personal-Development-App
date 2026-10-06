package com.example.flutter_application_1

/**
 * StepCountEngine — the pure (Android-free) state machine that owns today's step count.
 *
 * It is the only place where step arithmetic happens. Everything else (service,
 * notification, MainActivity, Flutter, SQLite) reads the value it produces through
 * [StepRepository].
 *
 * Counting model (delta-based, not baseline-based):
 *   - TYPE_STEP_COUNTER reports a cumulative count since boot. We remember the last
 *     value we have accounted for ([StepState.lastCounter]) and add only the positive
 *     difference to today's total. Feeding the same absolute value twice adds nothing,
 *     so any number of readers (service, worker, flushes) can never double count.
 *   - If the counter goes backwards the sensor was reset (reboot / sensor-hub restart):
 *     the new value is the number of steps since the reset, so it is added as-is.
 *     The previous total is untouched — a reboot can never lower the count.
 *   - New steps first go to a short "pending" quarantine. They are either committed
 *     to [StepState.todaySteps] or discarded by the gait validator. Committed steps are
 *     never taken back, so the displayed count is monotonic within a day.
 *   - The only legitimate decrease is the calendar day changing, handled by [rollTo].
 */
data class StepState(
    val date: String,
    /** Authoritative, validated step total for [date]. Never decreases within a day. */
    val todaySteps: Long,
    /** Last hardware counter value received, or -1 when unknown (first run / fresh install). */
    val lastCounter: Long,
    /** Steps received from the sensor but not yet validated. Not shown to the user. */
    val pendingSteps: Long = 0L,
    /** elapsedRealtimeNanos when the first currently-pending step arrived (0 if none). */
    val pendingSinceNanos: Long = 0L,
    /** Steps rejected by the validator today (diagnostics only). */
    val discardedToday: Long = 0L,
)

data class DayResult(val date: String, val steps: Long)

class StepCountEngine(initial: StepState) {

    companion object {
        /**
         * A single counter delta larger than this cannot be real walking between two
         * readings of a running service (it would be > 1 day of brisk walking). It means the
         * stored lastCounter belongs to a different sensor/boot, so we just re-anchor.
         */
        const val MAX_PLAUSIBLE_DELTA = 100_000L

        /**
         * A reading slightly below the last one is a late/duplicate delivery, not a reboot
         * (a rebooted counter restarts from 0). Such readings are ignored instead of being
         * misread as "everything since reset is new".
         */
        const val BACKWARD_GLITCH_TOLERANCE = 50L
    }

    var state: StepState = initial
        private set

    /**
     * Switch to [today] if the calendar day changed. Pending steps belong to the day they
     * were walked on, so they are committed to the finishing day first.
     * Returns the finished day's final total, or null if no rollover happened.
     */
    fun rollTo(today: String): DayResult? {
        if (state.date == today) return null
        val finished = DayResult(state.date, state.todaySteps + state.pendingSteps)
        state = StepState(
            date = today,
            todaySteps = 0L,
            lastCounter = state.lastCounter,
        )
        return finished
    }

    /** Feed an absolute TYPE_STEP_COUNTER value. Returns the number of new pending steps. */
    fun onCounter(value: Long, nowNanos: Long): Long {
        if (value < 0L) return 0L
        val last = state.lastCounter
        if (last < 0L) {
            // First reading ever: anchor only. We cannot know how many of these steps
            // were walked today, so none are attributed.
            state = state.copy(lastCounter = value)
            return 0L
        }
        if (value < last && last - value <= BACKWARD_GLITCH_TOLERANCE) return 0L
        val delta = when {
            value >= last -> value - last
            else -> value // counter reset (reboot): everything since the reset is new
        }
        if (delta > MAX_PLAUSIBLE_DELTA) {
            state = state.copy(lastCounter = value)
            return 0L
        }
        state = state.copy(lastCounter = value)
        addPending(delta, nowNanos)
        return delta
    }

    /** Fallback for devices that only have TYPE_STEP_DETECTOR (one event per step). */
    fun onDetectorStep(nowNanos: Long) = addPending(1L, nowNanos)

    private fun addPending(delta: Long, nowNanos: Long) {
        if (delta <= 0L) return
        val since = if (state.pendingSteps == 0L) nowNanos else state.pendingSinceNanos
        state = state.copy(pendingSteps = state.pendingSteps + delta, pendingSinceNanos = since)
    }

    fun isResolveDue(nowNanos: Long, windowNanos: Long): Boolean =
        state.pendingSteps > 0L && nowNanos - state.pendingSinceNanos >= windowNanos

    /**
     * Commit [accepted] of the pending steps and discard the rest.
     * Returns the number of steps added to today's total.
     */
    fun resolvePending(accepted: Long): Long {
        val pending = state.pendingSteps
        if (pending <= 0L) return 0L
        val ok = accepted.coerceIn(0L, pending)
        state = state.copy(
            todaySteps = state.todaySteps + ok,
            discardedToday = state.discardedToday + (pending - ok),
            pendingSteps = 0L,
            pendingSinceNanos = 0L,
        )
        return ok
    }

    /** Manually logged steps (from the app). Only ever increases the total. */
    fun addManual(steps: Long) {
        if (steps <= 0L) return
        state = state.copy(todaySteps = state.todaySteps + steps)
    }

    /**
     * Raise today's total to [steps] if it is higher (used once on migration / when
     * another persisted copy is known to be ahead). Never lowers the count.
     */
    fun raiseTodayTo(steps: Long) {
        if (steps > state.todaySteps) state = state.copy(todaySteps = steps)
    }

    /**
     * The state to write to disk. Pending steps are not persisted as steps; instead the
     * stored counter is rewound by the pending amount, so if the process dies those steps
     * reappear as a counter delta on the next reading and are validated again.
     */
    fun persistableState(): StepState {
        val s = state
        if (s.pendingSteps <= 0L || s.lastCounter < 0L) return s.copy(pendingSteps = 0L, pendingSinceNanos = 0L)
        val rewound = s.lastCounter - s.pendingSteps
        return s.copy(
            lastCounter = if (rewound >= 0L) rewound else s.lastCounter,
            pendingSteps = 0L,
            pendingSinceNanos = 0L,
        )
    }
}
