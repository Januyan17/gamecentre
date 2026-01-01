import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

/// Top-level callback for Android Alarm Manager (MUST be outside class)
@pragma('vm:entry-point')
void alarmCallback(int id, Map<String, dynamic> params) {
  // Show notification immediately
  _showNotificationFromCallback(id, params['title'], params['body']);
}

/// Show notification from callback - top-level function
@pragma('vm:entry-point')
Future<void> _showNotificationFromCallback(int id, String title, String body) async {
  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
  
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'service_time_up',
    'Service Time Up',
    channelDescription: 'Notifications when service time slots are completed',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
  );

  try {
    await notifications.show(
      id,
      title,
      body,
      notificationDetails,
    );
  } catch (e) {
    debugPrint('Error showing notification: $e');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const platform = MethodChannel('com.company.rowzow/battery');
  static const alarmChannel = MethodChannel('com.company.rowzow/alarm');

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    // Initialize Android Alarm Manager
    await AndroidAlarmManager.initialize();

    // Android initialization settings
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions for Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        
        try {
          await androidImplementation.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint('Could not request exact alarm permission: $e');
        }
        
        try {
          await androidImplementation.createNotificationChannel(
            const AndroidNotificationChannel(
              'service_time_up',
              'Service Time Up',
              description: 'Notifications when service time slots are completed with sound',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
              showBadge: true,
            ),
          );
        } catch (e) {
          debugPrint('Error creating notification channel: $e');
        }
      }
    }

    _initialized = true;
    
    // Request battery optimization exemption
    await requestBatteryOptimizationExemption();
  }

  /// Request battery optimization exemption
  Future<void> requestBatteryOptimizationExemption() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await platform.invokeMethod('requestBatteryOptimization');
      } catch (e) {
        debugPrint('Error requesting battery optimization exemption: $e');
      }
    }
  }
  
  /// Open auto-start settings
  Future<void> openAutoStartSettings() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await platform.invokeMethod('openAutoStartSettings');
      } catch (e) {
        debugPrint('Error opening auto-start settings: $e');
      }
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap if needed
  }

  /// Schedule a notification using android_alarm_manager_plus
  Future<void> scheduleServiceTimeUpNotification({
    required String serviceId,
    required String serviceType,
    required String customerName,
    required DateTime endTime,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (serviceType == 'VR') {
      return;
    }

    if (endTime.isBefore(DateTime.now())) {
      debugPrint('Cannot schedule notification in the past: $endTime');
      return;
    }

    final notificationId = serviceId.hashCode.abs();
    final delay = endTime.difference(DateTime.now());

    try {
      await AndroidAlarmManager.oneShot(
        delay,
        notificationId,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: false,
        params: {
          'title': 'Time Up: $serviceType',
          'body': '$serviceType session for $customerName has completed',
        },
      );
    } catch (e) {
      debugPrint('Error scheduling alarm: $e');
    }
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(String serviceId) async {
    final notificationId = serviceId.hashCode.abs();
    try {
      await AndroidAlarmManager.cancel(notificationId);
      await _notifications.cancel(notificationId);
    } catch (e) {
      debugPrint('Error canceling notification: $e');
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Show an immediate notification (for testing)
  Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'service_time_up',
      'Service Time Up',
      channelDescription: 'Notifications when service time slots are completed',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing immediate notification: $e');
    }
  }
}
