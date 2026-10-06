package com.example.flutter_application_1

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StepMidnightReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Trigger immediate background sync to snapshot yesterday's steps and init today's baseline
        StepBackgroundManager.enqueueImmediateSync(context)
        StepTrackingService.startAtMidnight(context)

        // Reschedule for next midnight
        StepBackgroundManager.scheduleMidnightAlarm(context)
    }
}
