package com.example.pillmate

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    try {
                        val id = call.argument<Int>("id")
                        val epochMillis = call.argument<Number>("epochMillis")?.toLong()
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val channelId = call.argument<String>("channelId")
                        val channelName = call.argument<String>("channelName")
                        val soundName = call.argument<String>("soundName")

                        if (
                            id == null ||
                            epochMillis == null ||
                            title == null ||
                            body == null ||
                            channelId == null ||
                            channelName == null ||
                            soundName == null
                        ) {
                            result.error("invalid_args", "Missing native notification arguments", null)
                            return@setMethodCallHandler
                        }

                        scheduleNativeNotification(
                            id = id,
                            epochMillis = epochMillis,
                            title = title,
                            body = body,
                            channelId = channelId,
                            channelName = channelName,
                            soundName = soundName
                        )
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("schedule_failed", error.message, null)
                    }
                }

                "cancelAll" -> {
                    try {
                        cancelAllNativeNotifications()
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("cancel_failed", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleNativeNotification(
        id: Int,
        epochMillis: Long,
        title: String,
        body: String,
        channelId: String,
        channelName: String,
        soundName: String
    ) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val safeTriggerAt = maxOf(epochMillis, System.currentTimeMillis() + 1_000L)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            PillmateAlarmReceiver.createIntent(
                context = this,
                id = id,
                title = title,
                body = body,
                channelId = channelId,
                channelName = channelName,
                soundName = soundName
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarmManager.canScheduleExactAlarms()
            ) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    safeTriggerAt,
                    pendingIntent
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    safeTriggerAt,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    safeTriggerAt,
                    pendingIntent
                )
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                safeTriggerAt,
                pendingIntent
            )
        }

        saveNativeNotificationId(id)
    }

    private fun cancelAllNativeNotifications() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ids = getNativeNotificationIds()

        ids.forEach { id ->
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                id,
                Intent(this, PillmateAlarmReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )

            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }

            notificationManager.cancel(id)
        }

        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(PREFS_IDS_KEY)
            .apply()
    }

    private fun saveNativeNotificationId(id: Int) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(PREFS_IDS_KEY, emptySet())?.toMutableSet()
            ?: mutableSetOf()
        ids.add(id.toString())
        prefs.edit().putStringSet(PREFS_IDS_KEY, ids).apply()
    }

    private fun getNativeNotificationIds(): Set<Int> {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getStringSet(PREFS_IDS_KEY, emptySet())
            ?.mapNotNull { it.toIntOrNull() }
            ?.toSet()
            ?: emptySet()
    }

    companion object {
        private const val CHANNEL_NAME = "pillmate/native_notifications"
        private const val PREFS_NAME = "pillmate_native_notifications"
        private const val PREFS_IDS_KEY = "scheduled_ids"
    }
}
