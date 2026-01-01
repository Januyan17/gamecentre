package com.company.rowzow

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Acquire wake lock to ensure notification is shown even if device is sleeping
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "Rowzow::NotificationWakeLock"
        )
        wakeLock.acquire(10000) // Hold for 10 seconds
        
        try {
            val notificationId = intent.getIntExtra("notificationId", 0)
            val title = intent.getStringExtra("title") ?: "Time Up"
            val body = intent.getStringExtra("body") ?: "Session completed"
            
            android.util.Log.d("NotificationReceiver", "Received alarm! ID: $notificationId")
            android.util.Log.d("NotificationReceiver", "Title: $title, Body: $body")
            
            createNotificationChannel(context)
            showNotification(context, notificationId, title, body)
            
            android.util.Log.d("NotificationReceiver", "Notification shown successfully!")
        } catch (e: Exception) {
            android.util.Log.e("NotificationReceiver", "Error showing notification", e)
            e.printStackTrace()
        } finally {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }
    
    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()
            
            val channel = NotificationChannel(
                "service_time_up",
                "Service Time Up",
                NotificationManager.IMPORTANCE_MAX // Changed to MAX
            ).apply {
                description = "Notifications when service time slots are completed"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                enableLights(true)
                setShowBadge(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                setBypassDnd(true) // Bypass Do Not Disturb
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    audioAttributes
                )
            }
            
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            
            android.util.Log.d("NotificationReceiver", "Notification channel created with MAX importance")
        }
    }
    
    private fun showNotification(context: Context, notificationId: Int, title: String, body: String) {
        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        
        val notificationBuilder = NotificationCompat.Builder(context, "service_time_up")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setSound(alarmSound)
            .setVibrate(longArrayOf(0, 1000, 500, 1000, 500, 1000))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(false)
            .setTimeoutAfter(60000) // Auto-dismiss after 1 minute
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setFullScreenIntent(null, true) // Request full screen (like alarm apps)
        
        try {
            val notificationManager = NotificationManagerCompat.from(context)
            
            // Check if notifications are enabled
            if (!notificationManager.areNotificationsEnabled()) {
                android.util.Log.e("NotificationReceiver", "Notifications are DISABLED in system settings!")
            }
            
            notificationManager.notify(notificationId, notificationBuilder.build())
            android.util.Log.d("NotificationReceiver", "Notification posted to system")
            
            // Also play alarm sound directly as backup
            try {
                val ringtone = RingtoneManager.getRingtone(context, alarmSound)
                ringtone.play()
                android.util.Log.d("NotificationReceiver", "Alarm sound played directly")
            } catch (e: Exception) {
                android.util.Log.e("NotificationReceiver", "Failed to play sound", e)
            }
        } catch (e: SecurityException) {
            android.util.Log.e("NotificationReceiver", "SecurityException showing notification", e)
            e.printStackTrace()
        }
    }
}

