package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Keeps the running task timer in a notification with Pause/Resume and End.
 *
 * The app (TaskTrackerProvider) owns the timer and saves the sessions. This
 * service only mirrors it, so it keeps showing after the app is closed, killed
 * or the phone is locked. Presses on the notification are applied to the
 * mirrored state at once and also written to an event log ("pause"/"resume"/
 * "end" with the time they happened); the app replays that log the next time
 * it runs, so the saved session matches exactly what the user did.
 */
class TaskTimerService : Service() {

    companion object {
        private const val PREFS = "grow_task_timer"
        private const val KEY_ACTIVE = "active"
        private const val KEY_TITLE = "title"
        private const val KEY_DONE_MS = "done_ms"
        private const val KEY_RUNNING_SINCE = "running_since_ms"
        private const val KEY_EVENTS = "events"

        private const val CHANNEL_ID = "grow_task_timer_channel"
        private const val NOTIFICATION_ID = 4210

        private const val ACTION_SHOW = "com.grow.app.timer.SHOW"
        private const val ACTION_PAUSE = "com.grow.app.timer.PAUSE"
        private const val ACTION_RESUME = "com.grow.app.timer.RESUME"
        private const val ACTION_END = "com.grow.app.timer.END"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Called by the app on every timer change while a timer exists. */
        fun sync(context: Context, title: String, doneMs: Long, runningSinceMs: Long) {
            prefs(context).edit()
                .putBoolean(KEY_ACTIVE, true)
                .putString(KEY_TITLE, title)
                .putLong(KEY_DONE_MS, doneMs)
                .putLong(KEY_RUNNING_SINCE, runningSinceMs)
                .apply()
            startWith(context, ACTION_SHOW)
        }

        /** Called by the app when its timer has ended (saved or discarded). */
        fun stop(context: Context) {
            prefs(context).edit().putBoolean(KEY_ACTIVE, false).apply()
            context.stopService(Intent(context, TaskTimerService::class.java))
            context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
        }

        /** Returns and clears the presses made on the notification. */
        fun drainEvents(context: Context): List<Map<String, Any>> {
            val p = prefs(context)
            val raw = p.getString(KEY_EVENTS, null) ?: return emptyList()
            p.edit().remove(KEY_EVENTS).apply()
            val out = ArrayList<Map<String, Any>>()
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    out.add(mapOf("action" to o.getString("a"), "atMs" to o.getLong("t")))
                }
            } catch (e: Exception) {
            }
            return out
        }

        /** Re-shows the notification after a reboot if a timer was left on. */
        fun restoreIfActive(context: Context) {
            if (prefs(context).getBoolean(KEY_ACTIVE, false)) startWith(context, ACTION_SHOW)
        }

        private fun startWith(context: Context, action: String) {
            val intent = Intent(context, TaskTimerService::class.java).setAction(action)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                android.util.Log.w("TaskTimerService", "could not start: $e")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        // Every startForegroundService() must be answered with startForeground().
        startForegroundCompat(buildNotification())

        val p = prefs(this)
        if (!p.getBoolean(KEY_ACTIVE, false)) {
            stopSelfNow()
            return START_NOT_STICKY
        }

        val now = System.currentTimeMillis()
        val runningSince = p.getLong(KEY_RUNNING_SINCE, 0L)
        when (intent?.action) {
            ACTION_PAUSE -> if (runningSince > 0L) {
                p.edit()
                    .putLong(KEY_DONE_MS, p.getLong(KEY_DONE_MS, 0L) + (now - runningSince))
                    .putLong(KEY_RUNNING_SINCE, 0L)
                    .apply()
                logEvent("pause", now)
            }
            ACTION_RESUME -> if (runningSince == 0L) {
                p.edit().putLong(KEY_RUNNING_SINCE, now).apply()
                logEvent("resume", now)
            }
            ACTION_END -> {
                logEvent("end", now)
                p.edit().putBoolean(KEY_ACTIVE, false).apply()
                stopSelfNow()
                return START_NOT_STICKY
            }
        }
        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, buildNotification())
        // Restarted by Android after the app is killed, it shows the timer again.
        return START_STICKY
    }

    private fun logEvent(action: String, atMs: Long) {
        val p = prefs(this)
        val arr = try {
            JSONArray(p.getString(KEY_EVENTS, "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        arr.put(JSONObject().put("a", action).put("t", atMs))
        p.edit().putString(KEY_EVENTS, arr.toString()).commit()
    }

    private fun stopSelfNow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun actionIntent(action: String, requestCode: Int): PendingIntent =
        PendingIntent.getService(
            this, requestCode,
            Intent(this, TaskTimerService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun buildNotification(): Notification {
        val p = prefs(this)
        val title = p.getString(KEY_TITLE, null) ?: "Task timer"
        val doneMs = p.getLong(KEY_DONE_MS, 0L)
        val runningSince = p.getLong(KEY_RUNNING_SINCE, 0L)
        val running = runningSince > 0L
        val now = System.currentTimeMillis()
        val elapsedMs = doneMs + if (running) (now - runningSince) else 0L

        val launch = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 4211, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_sprout_small)
            .setColor(Color.rgb(34, 197, 94))
            .setContentTitle("⏱ $title")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory("stopwatch")
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(launch)
            // Android 14+ lets people swipe it away; it comes straight back.
            .setDeleteIntent(actionIntent(ACTION_SHOW, 4212))

        if (running) {
            // The system clock keeps the time ticking with no updates needed.
            builder.setUsesChronometer(true)
                .setShowWhen(true)
                .setWhen(now - elapsedMs)
                .setContentText("Running")
                .addAction(0, "Pause", actionIntent(ACTION_PAUSE, 4213))
        } else {
            builder.setUsesChronometer(false)
                .setShowWhen(false)
                .setContentText("Paused at ${format(elapsedMs)}")
                .addAction(0, "Resume", actionIntent(ACTION_RESUME, 4214))
        }
        builder.addAction(0, "End", actionIntent(ACTION_END, 4215))
        return builder.build()
    }

    private fun format(ms: Long): String {
        val total = ms / 1000
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Task timer", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "The running task timer, with pause and end"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
            )
        }
    }
}
