package com.example.flutter_application_1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val validActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
        if (action in validActions) {
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
            val prefs = context.getSharedPreferences("grow_step_prefs", Context.MODE_PRIVATE)
            prefs.edit()
                .putLong("grow_baseline_$today", 0L)
                .putLong("grow_raw_steps", 0L)
                .putString("grow_step_date", today)
                .apply()
        }
    }
}
