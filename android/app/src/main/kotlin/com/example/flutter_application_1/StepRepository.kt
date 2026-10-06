package com.example.flutter_application_1

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors

/**
 * StepRepository — the ONE source of truth for the current step count.
 *
 * Every component reads from and reports to this process-wide singleton:
 *   Sensor (StepTrackingService only) → StepRepository.onCounter / onAccelerometer
 *   StepRepository → StepCountEngine (arithmetic) + GaitValidator (false-step rejection)
 *   StepRepository → SharedPreferences (state) + SQLite step_records (history)
 *   StepRepository → listeners: service notification, MainActivity → Flutter
 *
 * Nobody else computes steps. The notification, the app and the database therefore always
 * carry the same number, and that number never decreases within a calendar day.
 */
object StepRepository {

    private const val TAG = "StepRepository"
    private const val PREFS_NAME = "grow_step_prefs"

    // Single persisted state (v7). Older baseline/raw/discard keys are no longer used.
    private const val KEY_DATE = "grow_sc_date"
    private const val KEY_TODAY = "grow_sc_today_steps"
    private const val KEY_LAST_COUNTER = "grow_sc_last_counter"
    private const val KEY_DISCARDED = "grow_sc_discarded"
    private const val KEY_CURRENT_UID = "grow_current_uid"
    private const val KEY_GOAL = "grow_daily_step_goal"

    /** How long new steps wait for validation before being shown. */
    private const val VALIDATION_WINDOW_NANOS = 4_000_000_000L
    /** Accelerometer lead-in before the first pending step (hardware counters report late). */
    private const val VALIDATION_LEAD_IN_NANOS = 3_000_000_000L

    data class Snapshot(val date: String, val steps: Long, val goal: Int)

    fun interface Listener {
        fun onStepsChanged(snapshot: Snapshot)
    }

    private val lock = Any()
    private var appContext: Context? = null
    private lateinit var prefs: SharedPreferences
    private lateinit var engine: StepCountEngine
    private val validator = GaitValidator()
    private val listeners = CopyOnWriteArraySet<Listener>()
    private val mainHandler = Handler(Looper.getMainLooper())
    // All SQLite writes go through one thread, in order.
    private val dbExecutor = Executors.newSingleThreadExecutor()
    private val notifyLock = Any()
    private var lastNotified: Snapshot? = null

    /** Idempotent. Safe to call from any component before using the repository. */
    fun init(context: Context) {
        synchronized(lock) {
            if (appContext != null) return
            val app = context.applicationContext
            appContext = app
            prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            engine = StepCountEngine(loadState(app))
            rollIfNeededLocked()
            persistLocked(commit = true)
        }
    }

    private fun loadState(context: Context): StepState {
        val today = StepDbHelper.getLocalTodayString()
        if (prefs.contains(KEY_DATE)) {
            return StepState(
                date = prefs.getString(KEY_DATE, today) ?: today,
                todaySteps = prefs.getLong(KEY_TODAY, 0L),
                lastCounter = prefs.getLong(KEY_LAST_COUNTER, -1L),
                discardedToday = prefs.getLong(KEY_DISCARDED, 0L),
            )
        }
        // Migration from the old multi-counter design: start today from the persisted DB
        // value so nobody loses today's steps; the next sensor reading becomes the anchor.
        val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"
        val fromDb = StepDbHelper.readStepCount(context, uid, today)
        Log.i(TAG, "Migrating step state: starting today at $fromDb from database")
        return StepState(date = today, todaySteps = fromDb, lastCounter = -1L)
    }

    // ── Inputs (only StepTrackingService / DailyStepWorker call these) ───────────────

    fun onCounter(value: Long) {
        val now = SystemClock.elapsedRealtimeNanos()
        synchronized(lock) {
            if (appContext == null) return
            rollIfNeededLocked()
            engine.onCounter(value, now)
            resolveIfDueLocked(now, force = false)
            persistLocked(commit = false)
        }
        notifyIfChanged()
    }

    fun onDetectorStep() {
        val now = SystemClock.elapsedRealtimeNanos()
        synchronized(lock) {
            if (appContext == null) return
            rollIfNeededLocked()
            engine.onDetectorStep(now)
            resolveIfDueLocked(now, force = false)
            persistLocked(commit = false)
        }
        notifyIfChanged()
    }

    fun onAccelerometer(x: Float, y: Float, z: Float, eventTimestampNanos: Long) {
        // SensorEvent.timestamp is elapsedRealtimeNanos on modern devices; fall back to the
        // arrival time if a device uses another timebase so windows still line up.
        val now = SystemClock.elapsedRealtimeNanos()
        val ts = if (kotlin.math.abs(eventTimestampNanos - now) < 5_000_000_000L) eventTimestampNanos else now
        validator.addSample(x, y, z, ts)
    }

    /** Called periodically and on lifecycle events; validates pending steps when due. */
    fun tick(force: Boolean = false) {
        val now = SystemClock.elapsedRealtimeNanos()
        synchronized(lock) {
            if (appContext == null) return
            rollIfNeededLocked()
            if (resolveIfDueLocked(now, force)) persistLocked(commit = false)
        }
        notifyIfChanged()
    }

    // ── App actions ──────────────────────────────────────────────────────────────────

    fun addManualSteps(steps: Long): Snapshot {
        synchronized(lock) {
            rollIfNeededLocked()
            engine.addManual(steps)
            persistLocked(commit = true)
        }
        notifyIfChanged()
        return snapshot()
    }

    fun setGoal(goal: Int) {
        synchronized(lock) { prefs.edit().putInt(KEY_GOAL, goal).commit() }
        notifyIfChanged()
    }

    /** The signed-in user changed: mirror the current value into that user's DB row. */
    fun setCurrentUid(uid: String) {
        synchronized(lock) { prefs.edit().putString(KEY_CURRENT_UID, uid).commit() }
        synchronized(notifyLock) { lastNotified = null }
        notifyIfChanged()
    }

    // ── Outputs ──────────────────────────────────────────────────────────────────────

    fun snapshot(): Snapshot {
        synchronized(lock) {
            if (appContext != null) rollIfNeededLocked()
            return currentSnapshotLocked()
        }
    }

    fun addListener(l: Listener) {
        listeners.add(l)
        val s = snapshot()
        mainHandler.post { l.onStepsChanged(s) }
    }

    fun removeListener(l: Listener) {
        listeners.remove(l)
    }

    /** Make sure the latest value is on disk (service/app going away). */
    fun flush() {
        synchronized(lock) {
            if (appContext == null) return
            persistLocked(commit = true)
        }
    }

    // ── Internals (call with lock held) ──────────────────────────────────────────────

    private fun currentSnapshotLocked(): Snapshot {
        val goal = prefs.getInt(KEY_GOAL, 6000)
        return Snapshot(engine.state.date, engine.state.todaySteps, if (goal > 0) goal else 6000)
    }

    /** Legitimate daily reset: the only path that can lower the visible count. */
    private fun rollIfNeededLocked() {
        val today = StepDbHelper.getLocalTodayString()
        val finished = engine.rollTo(today) ?: return
        validator.reset()
        Log.i(TAG, "Day rollover ${finished.date} -> $today (final ${finished.steps} steps)")
        val ctx = appContext ?: return
        val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"
        dbExecutor.execute { StepDbHelper.writeStepRecord(ctx, uid, finished.date, finished.steps) }
        persistLocked(commit = true)
    }

    private fun resolveIfDueLocked(now: Long, force: Boolean): Boolean {
        val s = engine.state
        if (s.pendingSteps <= 0L) return false
        if (!force && !engine.isResolveDue(now, VALIDATION_WINDOW_NANOS)) return false
        val start = s.pendingSinceNanos - VALIDATION_LEAD_IN_NANOS
        val verdict = validator.evaluate(s.pendingSteps, start, now)
        engine.resolvePending(verdict.accepted)
        if (verdict.accepted < s.pendingSteps) {
            Log.d(TAG, "Rejected ${s.pendingSteps - verdict.accepted} steps: ${verdict.reason} " +
                "(cadence=${verdict.cadenceHz}Hz periodicity=${verdict.periodicity} rms=${verdict.rms})")
        }
        return true
    }

    private fun persistLocked(commit: Boolean) {
        val s = engine.persistableState()
        val editor = prefs.edit()
            .putString(KEY_DATE, s.date)
            .putLong(KEY_TODAY, s.todaySteps)
            .putLong(KEY_LAST_COUNTER, s.lastCounter)
            .putLong(KEY_DISCARDED, s.discardedToday)
        if (commit) editor.commit() else editor.apply()
    }

    private fun notifyIfChanged() {
        synchronized(notifyLock) {
            val snap = snapshot()
            if (snap == lastNotified) return
            val previous = lastNotified
            lastNotified = snap
            // The database mirrors the authoritative value (writeStepRecord keeps the max, so an
            // older queued write can never lower it). Goal-only changes don't need a write.
            val ctx = appContext
            if (ctx != null && (previous == null || previous.steps != snap.steps || previous.date != snap.date)) {
                val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"
                dbExecutor.execute { StepDbHelper.writeStepRecord(ctx, uid, snap.date, snap.steps) }
            }
            // Posted under the lock, so listeners always receive snapshots in order.
            mainHandler.post { for (l in listeners) l.onStepsChanged(snap) }
        }
    }
}
