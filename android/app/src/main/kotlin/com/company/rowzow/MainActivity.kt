package com.company.rowzow

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.company.rowzow/battery"
    private val ALARM_CHANNEL = "com.company.rowzow/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Battery optimization channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBatteryOptimization" -> {
                    val success = requestBatteryOptimization()
                    result.success(success)
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Alarm scheduling channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 0
                    val title = call.argument<String>("title") ?: "Time Up"
                    val body = call.argument<String>("body") ?: "Session completed"
                    val scheduledTimeMillis = call.argument<Long>("scheduledTimeMillis") ?: 0
                    
                    val success = scheduleAlarm(notificationId, title, body, scheduledTimeMillis)
                    result.success(success)
                }
                "cancelAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 0
                    cancelAlarm(notificationId)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestBatteryOptimization(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                val packageName = packageName
                
                if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    true
                } else {
                    true
                }
            } else {
                true
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
    
    private fun openAutoStartSettings() {
        try {
            // Try Xiaomi/MIUI
            val intent = Intent().apply {
                component = android.content.ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                // Fallback to general app settings
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e2: Exception) {
                e2.printStackTrace()
            }
        }
    }
    
    private fun scheduleAlarm(notificationId: Int, title: String, body: String, scheduledTimeMillis: Long): Boolean {
        return try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            android.util.Log.d("MainActivity", "Scheduling alarm:")
            android.util.Log.d("MainActivity", "  ID: $notificationId")
            android.util.Log.d("MainActivity", "  Title: $title")
            android.util.Log.d("MainActivity", "  Scheduled for: $scheduledTimeMillis")
            android.util.Log.d("MainActivity", "  Current time: ${System.currentTimeMillis()}")
            android.util.Log.d("MainActivity", "  Time until alarm: ${scheduledTimeMillis - System.currentTimeMillis()} ms")
            
            val intent = Intent(this, NotificationReceiver::class.java).apply {
                putExtra("notificationId", notificationId)
                putExtra("title", title)
                putExtra("body", body)
                // Add flags to ensure intent is delivered
                addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Cancel any existing alarm with same ID
            alarmManager.cancel(pendingIntent)
            
            // Use setExactAndAllowWhileIdle for maximum reliability
            // This is the same method used by alarm clock apps
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    scheduledTimeMillis,
                    pendingIntent
                )
                android.util.Log.d("MainActivity", "✅ Alarm scheduled using setExactAndAllowWhileIdle")
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    scheduledTimeMillis,
                    pendingIntent
                )
                android.util.Log.d("MainActivity", "✅ Alarm scheduled using setExact")
            }
            
            // Verify the alarm can be scheduled
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val canSchedule = alarmManager.canScheduleExactAlarms()
                android.util.Log.d("MainActivity", "Can schedule exact alarms: $canSchedule")
                if (!canSchedule) {
                    android.util.Log.e("MainActivity", "⚠️ Cannot schedule exact alarms! User needs to grant permission.")
                }
            }
            
            true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Error scheduling alarm", e)
            e.printStackTrace()
            false
        }
    }
    
    private fun cancelAlarm(notificationId: Int) {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, NotificationReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
