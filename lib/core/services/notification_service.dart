import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Top-level callback for Android Alarm Manager (MUST be outside class)
@pragma('vm:entry-point')
void alarmCallback(int id, Map<String, dynamic> params) {
  // Check if session is still active before showing notification
  _checkAndShowNotification(id, params);
}

/// Check if session is still active and show notification only if active
@pragma('vm:entry-point')
Future<void> _checkAndShowNotification(
  int id,
  Map<String, dynamic> params,
) async {
  try {
    // Extract serviceId from params (we need to pass it when scheduling)
    final serviceId = params['serviceId'] as String?;
    final sessionId = params['sessionId'] as String?;

    if (serviceId == null || sessionId == null) {
      debugPrint('⚠️ Notification callback: Missing serviceId or sessionId');
      return;
    }

    debugPrint('🔔 Alarm fired for service: $serviceId, session: $sessionId');

    // Initialize Firestore in background isolate
    final firestore = FirebaseFirestore.instance;

    // Check if session is still active in Firestore with timeout
    DocumentSnapshot? sessionDoc;
    bool checkFailed = false;

    try {
      sessionDoc = await firestore
          .collection('active_sessions')
          .doc(sessionId)
          .get()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint(
        '⚠️ Firestore query failed: $e. Will show notification anyway.',
      );
      checkFailed = true;
    }

    // If Firestore check failed (network/initialization error), show notification anyway
    if (checkFailed || sessionDoc == null) {
      final title = params['title'] as String? ?? 'Time Up';
      final body = params['body'] as String? ?? 'Service time completed';
      debugPrint(
        '⚠️ Firestore check failed, showing notification anyway: $title - $body',
      );
      await _showNotificationFromCallback(id, title, body);
      return;
    }

    // Only show notification if session is still active
    if (!sessionDoc.exists) {
      debugPrint(
        'ℹ️ Session $sessionId is no longer active. Not showing notification.',
      );
      return;
    }

    final sessionData = sessionDoc.data() as Map<String, dynamic>?;
    if (sessionData == null) {
      debugPrint(
        'ℹ️ Session $sessionId has no data. Not showing notification.',
      );
      return;
    }

    // Check if the service still exists in the session
    final services = List<Map<String, dynamic>>.from(
      sessionData['services'] ?? [],
    );
    final serviceExists = services.any(
      (service) => (service['id'] as String? ?? '') == serviceId,
    );

    if (!serviceExists) {
      debugPrint(
        'ℹ️ Service $serviceId no longer exists in session $sessionId. Not showing notification.',
      );
      return;
    }

    // Session is still active and service exists, show notification
    final title = params['title'] as String? ?? 'Time Up';
    final body = params['body'] as String? ?? 'Service time completed';
    debugPrint('✅ Showing notification: $title - $body');
    await _showNotificationFromCallback(id, title, body);
  } catch (e, stackTrace) {
    debugPrint('❌ Error checking session status: $e');
    debugPrint('Stack trace: $stackTrace');
    // On error, show notification anyway to ensure user is notified
    try {
      final title = params['title'] as String? ?? 'Time Up';
      final body = params['body'] as String? ?? 'Service time completed';
      debugPrint(
        '⚠️ Showing notification despite error to ensure user is notified',
      );
      await _showNotificationFromCallback(id, title, body);
    } catch (e2) {
      debugPrint('❌ Failed to show notification even after error: $e2');
    }
  }
}

/// Show notification from callback - top-level function
@pragma('vm:entry-point')
Future<void> _showNotificationFromCallback(
  int id,
  String title,
  String body,
) async {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

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
    await notifications.show(id, title, body, notificationDetails);
  } catch (e) {
    debugPrint('Error showing notification: $e');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
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
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
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
      final androidImplementation =
          _notifications
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

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
              description:
                  'Notifications when service time slots are completed with sound',
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
    required String sessionId,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    // VR notifications are now enabled (based on games)

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
          'serviceId': serviceId,
          'sessionId': sessionId,
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

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'service_time_up',
          'Service Time Up',
          channelDescription:
              'Notifications when service time slots are completed',
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
