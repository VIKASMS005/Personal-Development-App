package com.example.flutter_application_1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val validActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
        if (action in validActions) {
            val today = StepDbHelper.getLocalTodayString()
            val prefs = context.getSharedPreferences("grow_step_prefs", Context.MODE_PRIVATE)
            val uid = prefs.getString("grow_current_uid", "local_user") ?: "local_user"

            // BUG 2 FIX: Read the last saved step count from SQLite before resetting.
            // After a reboot the hardware counter restarts at 0, so we must treat
            // the previously saved count as a pre-reboot offset so that post-reboot
            // steps correctly accumulate on top of what was already achieved today.
            val preRebootSteps = readStepsFromDb(context, uid, today)

            prefs.edit()
                // Baseline = 0 because hardware resets to 0 after reboot
                .putLong("grow_baseline_$today", 0L)
                // Store the pre-reboot accumulated count so Dart can use it as offset
                .putLong("grow_pre_reboot_offset_$today", preRebootSteps)
                .putLong("grow_raw_steps", 0L)
                .putString("grow_step_date", today)
                .apply()

            // Schedule background daily step tracking and midnight alarm
            StepBackgroundManager.schedulePeriodicSync(context)
            StepBackgroundManager.scheduleMidnightAlarm(context)
            StepTrackingService.start(context)
        }
    }

    /** Read the current step_count for (uid, date) from SQLite, or 0 if not found. */
    private fun readStepsFromDb(context: Context, uid: String, dateStr: String): Long {
        return try {
            val dbFile = context.getDatabasePath("grow_app_v2.db")
            if (!dbFile.exists()) return 0L
            val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READONLY)
            try {
                val cursor = db.rawQuery(
                    "SELECT step_count FROM step_records WHERE uid = ? AND date = ? LIMIT 1",
                    arrayOf(uid, dateStr)
                )
                var steps = 0L
                if (cursor.moveToFirst()) {
                    steps = cursor.getLong(0)
                }
                cursor.close()
                steps
            } finally {
                db.close()
            }
        } catch (_: Exception) { 0L }
    }
}
