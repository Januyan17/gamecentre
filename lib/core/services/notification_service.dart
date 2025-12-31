import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // Adjust to your timezone

    // Android initialization settings
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings (optional, for iOS support)
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
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap if needed
    debugPrint('Notification tapped: ${response.payload}');
  }

  /// Schedule a notification for when a service time slot completes
  /// 
  /// [serviceId] - Unique ID for the service
  /// [serviceType] - Type of service (PS4, PS5, Theatre, Simulator)
  /// [customerName] - Name of the customer
  /// [endTime] - When the service will end (DateTime)
  Future<void> scheduleServiceTimeUpNotification({
    required String serviceId,
    required String serviceType,
    required String customerName,
    required DateTime endTime,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    // Only schedule for PS4, PS5, Theatre, and Car Simulator (not VR)
    if (serviceType == 'VR') {
      return;
    }

    // Ensure endTime is in the future
    if (endTime.isBefore(DateTime.now())) {
      debugPrint('Cannot schedule notification in the past: $endTime');
      return;
    }

    // Convert to local timezone
    final scheduledDate = tz.TZDateTime.from(endTime, tz.local);

    // Create notification details
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'service_time_up',
      'Service Time Up',
      channelDescription: 'Notifications when service time slots are completed',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Schedule the notification
    await _notifications.zonedSchedule(
      serviceId.hashCode, // Use hash code as notification ID
      'Time Up: $serviceType',
      '$serviceType session for $customerName has completed',
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint('Scheduled notification for $serviceType at ${scheduledDate.toString()}');
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(String serviceId) async {
    await _notifications.cancel(serviceId.hashCode);
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
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notificationDetails,
    );
  }
}

