package com.example.flutter_application_1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts step tracking after a reboot.
 *
 * No step bookkeeping happens here any more. The hardware counter restarts at 0 after a
 * reboot; StepRepository sees the counter go backwards and adds the post-boot steps on top
 * of today's persisted total, so nothing is lost and nothing is reset.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val validActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
        if (action in validActions) {
            StepRepository.init(context)
            StepBackgroundManager.schedulePeriodicSync(context)
            StepBackgroundManager.scheduleMidnightAlarm(context)
            StepTrackingService.start(context)
        }
    }
}
