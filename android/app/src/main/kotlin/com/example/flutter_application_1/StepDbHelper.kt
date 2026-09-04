package com.example.flutter_application_1

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

object StepDbHelper {

    private const val PREFS_NAME = "grow_step_prefs"
    private const val KEY_RAW_STEPS = "grow_raw_steps"
    private const val KEY_STEP_DATE = "grow_step_date"
    private const val KEY_BASELINE_PREFIX = "grow_baseline_"
    private const val KEY_CURRENT_UID = "grow_current_uid"

    /**
     * Format today's local date as canonical YYYY-MM-DD using Locale.US (ASCII digits).
     */
    fun getLocalTodayString(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }

    /**
     * Checks if a calendar day rollover occurred. If so, snapshots yesterday's accumulated
     * steps to SQLite, initializes today's baseline to rawSteps, and updates the recorded date.
     *
     * @return true if a date rollover was detected and processed.
     */
    @Synchronized
    fun handleDateRollover(context: Context, rawSteps: Long, todayDateStr: String): Boolean {
        if (rawSteps <= 0L) return false

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lastRecordedDate = prefs.getString(KEY_STEP_DATE, "") ?: ""
        val uid = prefs.getString(KEY_CURRENT_UID, "local_user") ?: "local_user"

        if (lastRecordedDate.isNotEmpty() && lastRecordedDate != todayDateStr) {
            val lastBaseline = prefs.getLong(KEY_BASELINE_PREFIX + lastRecordedDate, -1L)
            val effectiveBaseline = if (lastBaseline >= 0L) lastBaseline else 0L
            if (rawSteps >= effectiveBaseline) {
                val stepsForYesterday = rawSteps - effectiveBaseline
                writeStepRecord(context, uid, lastRecordedDate, stepsForYesterday, forceOverwrite = true)
            }

            val editor = prefs.edit()
            // Set today's baseline to rawSteps at the moment of day transition
            editor.putLong(KEY_BASELINE_PREFIX + todayDateStr, rawSteps)
            editor.putString(KEY_STEP_DATE, todayDateStr)
            editor.putLong(KEY_RAW_STEPS, rawSteps)
            editor.commit()

            // Initialize today's record in SQLite with 0 steps
            writeStepRecord(context, uid, todayDateStr, 0L, forceOverwrite = true)
            return true
        } else if (lastRecordedDate.isEmpty()) {
            val editor = prefs.edit()
            val todayBaselineKey = KEY_BASELINE_PREFIX + todayDateStr
            if (!prefs.contains(todayBaselineKey)) {
                editor.putLong(todayBaselineKey, rawSteps)
            }
            editor.putString(KEY_STEP_DATE, todayDateStr)
            editor.putLong(KEY_RAW_STEPS, rawSteps)
            editor.commit()
        }
        return false
    }

    /**
     * Write or update a step record for a specific calendar date in SQLite.
     * Consolidates any duplicate rows so exactly ONE entry exists per (uid, date).
     */
    @Synchronized
    fun writeStepRecord(context: Context, uid: String, dateStr: String, steps: Long, forceOverwrite: Boolean = false) {
        try {
            val dbFile = context.getDatabasePath("grow_app_v2.db")
            if (!dbFile.exists()) return

            val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READWRITE)
            try {
                val nowIso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
                val cursor = db.rawQuery(
                    "SELECT id, goal, step_count FROM step_records WHERE uid = ? AND date = ?",
                    arrayOf(uid, dateStr)
                )

                var existingId: String? = null
                var goal = 6000
                var existingSteps = 0L
                val duplicateIds = mutableListOf<String>()

                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    if (existingId == null) {
                        existingId = id
                        goal = cursor.getInt(1)
                        existingSteps = cursor.getLong(2)
                    } else {
                        // Consolidate any duplicate rows
                        existingSteps += cursor.getLong(2)
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
        } catch (_: Exception) {}
    }
}
