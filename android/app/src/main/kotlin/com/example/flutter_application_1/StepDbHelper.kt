package com.example.flutter_application_1

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

object StepDbHelper {

    /**
     * Format today's local date as canonical YYYY-MM-DD using Locale.US (ASCII digits).
     */
    fun getLocalTodayString(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }

    /** Read the stored step_count for (uid, date), or 0 if there is none. */
    @Synchronized
    fun readStepCount(context: Context, uid: String, dateStr: String): Long {
        return try {
            val dbFile = context.getDatabasePath("grow_app_v2.db")
            if (!dbFile.exists()) return 0L
            val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY)
            try {
                db.rawQuery(
                    "SELECT MAX(step_count) FROM step_records WHERE uid = ? AND date = ?",
                    arrayOf(uid, dateStr)
                ).use { c -> if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else 0L }
            } finally {
                db.close()
            }
        } catch (_: Exception) { 0L }
    }

    /**
     * Write or update a step record for a specific calendar date in SQLite.
     * Consolidates any duplicate rows so exactly ONE entry exists per (uid, date).
     *
     * [steps] is the authoritative total from StepRepository. Unless [forceOverwrite] is set,
     * the stored value only ever goes up, so a late/queued write can never lower it.
     */
    @Synchronized
    fun writeStepRecord(context: Context, uid: String, dateStr: String, steps: Long, forceOverwrite: Boolean = false): Boolean {
        try {
            val dbFile = context.getDatabasePath("grow_app_v2.db")
            if (!dbFile.exists()) return false

            val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READWRITE)
            try {
                val nowIso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
                val cursor = db.rawQuery(
                    "SELECT id, goal, step_count FROM step_records WHERE uid = ? AND date = ?",
                    arrayOf(uid, dateStr)
                )

                var existingId: String? = null
                // FIX C2: Read user's chosen goal from native prefs instead of hardcoding 6000.
                // grow_daily_step_goal is written by MainActivity.setStepGoal which Flutter calls
                // whenever StepProvider.updateDailyGoal() is called.
                val stepPrefs = context.getSharedPreferences("grow_step_prefs", 0)
                val userGoal = stepPrefs.getInt("grow_daily_step_goal", 6000)
                var goal = userGoal // Default to user's actual goal, not hardcoded 6000
                var existingSteps = 0L
                val duplicateIds = mutableListOf<String>()

                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    if (existingId == null) {
                        existingId = id
                        // If the existing row has a goal > 0, use it (may be more up-to-date);
                        // otherwise fall back to the user's prefs goal
                        val rowGoal = cursor.getInt(1)
                        goal = if (rowGoal > 0) rowGoal else userGoal
                        existingSteps = cursor.getLong(2)
                    } else {
                        // Consolidate any duplicate rows — use MAX not SUM since each row is a
                        // daily cumulative total, not an incremental count. Summing would double-count.
                        val dupSteps = cursor.getLong(2)
                        if (dupSteps > existingSteps) existingSteps = dupSteps
                        duplicateIds.add(id)
                    }
                }
                cursor.close()

                // Delete duplicate rows to strictly enforce 1 row per (uid, date)
                for (dupId in duplicateIds) {
                    db.delete("step_records", "id = ?", arrayOf(dupId))
                }

                val effectiveSteps = if (forceOverwrite) steps else maxOf(existingSteps, steps)

                val cv = ContentValues().apply {
                    put("uid", uid)
                    put("date", dateStr)
                    put("step_count", effectiveSteps)
                    put("goal", goal)
                    put("calories", effectiveSteps * 0.04)
                    put("distance_km", effectiveSteps * 0.00075)
                    put("active_minutes", (effectiveSteps / 100).toInt())
                    put("updated_at", nowIso)
                }

                if (existingId != null) {
                    db.update("step_records", cv, "id = ?", arrayOf(existingId))
                } else {
                    cv.put("id", UUID.randomUUID().toString())
                    db.insert("step_records", null, cv)
                }
            } finally {
                db.close()
            }
            return true
        } catch (_: Exception) {}
        return false
    }
}
