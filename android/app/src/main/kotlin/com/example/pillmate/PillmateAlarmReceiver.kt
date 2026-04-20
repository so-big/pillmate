package com.example.pillmate

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

class PillmateAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Pillmate"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        val channelId = intent.getStringExtra(EXTRA_CHANNEL_ID) ?: DEFAULT_CHANNEL_ID
        val channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: DEFAULT_CHANNEL_NAME
        val soundName = intent.getStringExtra(EXTRA_SOUND_NAME) ?: DEFAULT_SOUND_NAME

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val soundUri = Uri.parse("android.resource://${context.packageName}/raw/$soundName")
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Pillmate medicine alarm"
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(soundUri, audioAttributes)
        }
        notificationManager.createNotificationChannel(channel)

        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent()
        val contentIntent = PendingIntent.getActivity(
            context,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)
            .setSound(soundUri, audioAttributes)
            .build()

        notificationManager.notify(id, notification)
        removeNativeNotificationId(context, id)
    }

    private fun removeNativeNotificationId(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(PREFS_IDS_KEY, emptySet())?.toMutableSet()
            ?: mutableSetOf()
        ids.remove(id.toString())
        prefs.edit().putStringSet(PREFS_IDS_KEY, ids).apply()
    }

    companion object {
        private const val PREFS_NAME = "pillmate_native_notifications"
        private const val PREFS_IDS_KEY = "scheduled_ids"

        private const val EXTRA_ID = "id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val EXTRA_CHANNEL_ID = "channel_id"
        private const val EXTRA_CHANNEL_NAME = "channel_name"
        private const val EXTRA_SOUND_NAME = "sound_name"

        private const val DEFAULT_CHANNEL_ID = "pillmate_native_alarm_v1"
        private const val DEFAULT_CHANNEL_NAME = "Pillmate Alarm"
        private const val DEFAULT_SOUND_NAME = "a01_clock_alarm_normal_30_sec"

        fun createIntent(
            context: Context,
            id: Int,
            title: String,
            body: String,
            channelId: String,
            channelName: String,
            soundName: String
        ): Intent {
            return Intent(context, PillmateAlarmReceiver::class.java).apply {
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_CHANNEL_ID, channelId)
                putExtra(EXTRA_CHANNEL_NAME, channelName)
                putExtra(EXTRA_SOUND_NAME, soundName)
            }
        }
    }
}
