import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

/// Top-level callback for Android Alarm Manager (MUST be outside class)
@pragma('vm:entry-point')
void alarmCallback(int id, Map<String, dynamic> params) {
  debugPrint('🔔 alarmCallback called with ID: $id');
  debugPrint('🔔 Params: $params');
  // Check if session is still active before showing notification
  // Use runZonedGuarded to ensure async errors are caught
  _checkAndShowNotification(id, params).catchError((error, stackTrace) {
    debugPrint('❌ Error in alarmCallback: $error');
    debugPrint('Stack trace: $stackTrace');
  });
}

/// Check if session is still active and show notification only if active
@pragma('vm:entry-point')
Future<void> _checkAndShowNotification(int id, Map<String, dynamic> params) async {
  try {
    debugPrint('🔔 _checkAndShowNotification called');
    debugPrint('🔔 Params received: $params');

    // Initialize Firebase in background isolate (if not already initialized)
    // IMPORTANT: Firebase must be initialized in the background isolate
    try {
      await Firebase.initializeApp();
      debugPrint('✅ Firebase initialized in background isolate');
    } catch (e) {
      // Firebase might already be initialized, which is fine
      if (e.toString().contains('already been initialized')) {
        debugPrint('ℹ️ Firebase already initialized in background isolate');
      } else {
        debugPrint('⚠️ Error initializing Firebase in background isolate: $e');
        // Continue anyway - we'll try to use Firestore
      }
    }

    // Extract serviceId from params (we need to pass it when scheduling)
    final serviceId = params['serviceId'] as String?;
    final sessionId = params['sessionId'] as String?;

    if (serviceId == null || sessionId == null) {
      debugPrint('⚠️ Notification callback: Missing serviceId or sessionId');
      debugPrint('   serviceId: $serviceId');
      debugPrint('   sessionId: $sessionId');
      return;
    }

    debugPrint('🔔 Alarm fired for service: $serviceId, session: $sessionId');

    // Get Firestore instance (Firebase should now be initialized)
    final firestore = FirebaseFirestore.instance;
    debugPrint('✅ Firestore instance obtained');

    // Get service type from params to check notification toggle first
    final serviceType = params['serviceType'] as String? ?? '';

    // Check notification toggle setting FIRST (before checking session status)
    bool notificationsEnabled = true;
    try {
      final notificationDoc = await firestore
          .collection('settings')
          .doc('notifications')
          .get()
          .timeout(const Duration(seconds: 3));
      if (notificationDoc.exists) {
        final data = notificationDoc.data();
        // Map service type to setting key (case-insensitive)
        final serviceTypeLower = serviceType.toLowerCase();
        String settingKey;
        if (serviceTypeLower == 'ps4') {
          settingKey = 'ps4';
        } else if (serviceTypeLower == 'ps5') {
          settingKey = 'ps5';
        } else if (serviceTypeLower == 'vr') {
          settingKey = 'vr';
        } else if (serviceTypeLower == 'simulator') {
          settingKey = 'simulator';
        } else if (serviceTypeLower == 'theatre') {
          settingKey = 'theatre';
        } else {
          // Unknown service type, default to enabled
          settingKey = '';
        }

        if (settingKey.isNotEmpty) {
          notificationsEnabled = data?[settingKey] ?? true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not check notification setting, defaulting to enabled: $e');
      // Default to enabled if check fails
    }

    // If notifications are disabled for this service type, don't show notification
    if (!notificationsEnabled) {
      debugPrint('ℹ️ Notifications are disabled for $serviceType. Not showing notification.');
      return;
    }

    // Check if session is still active in Firestore with timeout
    // Use a simpler approach: if session exists in active_sessions and is not closed, show notification
    DocumentSnapshot? sessionDoc;
    bool sessionIsClosed = false;

    debugPrint('🔍 Checking session status in Firestore...');

    try {
      // Try to get session from active_sessions first
      sessionDoc = await firestore
          .collection('active_sessions')
          .doc(sessionId)
          .get()
          .timeout(const Duration(seconds: 10));

      debugPrint('🔍 Firestore query completed. Session exists: ${sessionDoc.exists}');

      if (sessionDoc.exists) {
        final sessionData = sessionDoc.data() as Map<String, dynamic>?;
        if (sessionData != null) {
          final status = (sessionData['status'] as String? ?? 'active').toLowerCase().trim();
          debugPrint('🔍 Session status: $status');
          if (status == 'closed') {
            sessionIsClosed = true;
            debugPrint(
              'ℹ️ Session $sessionId is closed in active_sessions. Not showing notification.',
            );
          } else {
            // Session exists and is active - proceed to show notification
            debugPrint(
              '✅ Session $sessionId is active in active_sessions (status: $status). Will show notification.',
            );
          }
        } else {
          // Session exists but no data - treat as active (might be a race condition)
          debugPrint(
            '⚠️ Session $sessionId exists but has no data. Treating as active and showing notification.',
          );
        }
      } else {
        // Session not in active_sessions - check if it's closed
        debugPrint(
          '⚠️ Session $sessionId not found in active_sessions. Checking closed sessions...',
        );

        // Check closed sessions to confirm it's not closed
        try {
          final today = DateTime.now();
          final dateId =
              '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

          final closedSessionDoc = await firestore
              .collection('days')
              .doc(dateId)
              .collection('sessions')
              .doc(sessionId)
              .get()
              .timeout(const Duration(seconds: 5));

          if (closedSessionDoc.exists) {
            sessionIsClosed = true;
            debugPrint('ℹ️ Session $sessionId is in closed sessions. Not showing notification.');
          } else {
            // Check yesterday too
            final yesterday = today.subtract(const Duration(days: 1));
            final yesterdayId =
                '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

            final yesterdayClosedDoc = await firestore
                .collection('days')
                .doc(yesterdayId)
                .collection('sessions')
                .doc(sessionId)
                .get()
                .timeout(const Duration(seconds: 5));

            if (yesterdayClosedDoc.exists) {
              sessionIsClosed = true;
              debugPrint(
                'ℹ️ Session $sessionId is in closed sessions (yesterday). Not showing notification.',
              );
            } else {
              // Session not found in active or closed - might be deleted
              // But if we scheduled a notification, the session was active at that time
              // So show the notification anyway (better to show than miss)
              debugPrint(
                '⚠️ Session $sessionId not found in active or closed sessions. Showing notification anyway (was active when scheduled).',
              );
              // Don't set sessionIsClosed = true, allow notification to show
            }
          }
        } catch (e) {
          debugPrint('⚠️ Could not check closed sessions: $e');
          // If we can't verify, show notification anyway (was active when scheduled)
          debugPrint('⚠️ Showing notification anyway since we cannot verify status.');
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ Firestore query failed: $e. Showing notification anyway (was active when scheduled).',
      );
      // On error, show notification anyway since it was scheduled for an active session
      // This prevents missing notifications due to temporary network issues
    }

    // CRITICAL: Only show notifications for active sessions
    // If session is explicitly closed, don't show notification
    if (sessionIsClosed) {
      debugPrint('ℹ️ Session $sessionId is closed. Not showing notification.');
      return;
    }

    debugPrint('✅ Session check passed. Proceeding to show notification.');

    // Check if notification was already shown (prevent duplicates)
    // Use the same key format as dashboard page
    final notificationKey = 'time_up_${sessionId}_$serviceId';
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyNotified = prefs.getBool(notificationKey) ?? false;
      
      if (alreadyNotified) {
        debugPrint('ℹ️ Notification already shown for service $serviceId (session $sessionId). Skipping duplicate.');
        return;
      }
      
      // Mark as notified FIRST to prevent race conditions
      await prefs.setBool(notificationKey, true);
      debugPrint('✅ Marked notification as shown in SharedPreferences');
    } catch (e) {
      debugPrint('⚠️ Could not check SharedPreferences for duplicate prevention: $e');
      // Continue to show notification if SharedPreferences check fails
    }

    // Get session data (optional - we'll show notification even without it)
    Map<String, dynamic>? sessionData;
    if (sessionDoc != null && sessionDoc.exists) {
      sessionData = sessionDoc.data() as Map<String, dynamic>?;
    }

    // If we don't have session data, try to fetch it one more time (optional)
    if (sessionData == null && !sessionIsClosed) {
      try {
        final finalDoc = await firestore
            .collection('active_sessions')
            .doc(sessionId)
            .get()
            .timeout(const Duration(seconds: 3));
        if (finalDoc.exists) {
          sessionData = finalDoc.data();
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch session data: $e');
      }
    }

    // Show notification - we've already verified session is not closed
    // Even if we don't have session data, show notification since it was scheduled for an active session
    final title = params['title'] as String? ?? 'Time Up';
    final body = params['body'] as String? ?? 'Service time completed';
    debugPrint('✅ Showing notification: $title - $body');
    debugPrint('   Service ID: $serviceId');
    debugPrint('   Session ID: $sessionId');
    await _showNotificationFromCallback(id, title, body);
    debugPrint('✅ Notification shown successfully');
  } catch (e, stackTrace) {
    debugPrint('❌ Error checking session status: $e');
    debugPrint('Stack trace: $stackTrace');
    // If there's an error, check for duplicates before showing notification
    // Extract serviceId and sessionId from params again (they might not be in scope)
    final errorServiceId = params['serviceId'] as String?;
    final errorSessionId = params['sessionId'] as String?;
    
    if (errorServiceId != null && errorSessionId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final notificationKey = 'time_up_${errorSessionId}_$errorServiceId';
        final alreadyNotified = prefs.getBool(notificationKey) ?? false;
        
        if (alreadyNotified) {
          debugPrint('ℹ️ Notification already shown (error case). Skipping duplicate.');
          return;
        }
        
        // Mark as notified FIRST to prevent race conditions
        await prefs.setBool(notificationKey, true);
      } catch (prefsError) {
        debugPrint('⚠️ Could not check SharedPreferences in error handler: $prefsError');
      }
    }
    
    // If there's an error, show notification anyway since it was scheduled for an active session
    // Better to show a notification than miss one
    debugPrint(
      '⚠️ Error occurred, but showing notification anyway since it was scheduled for an active session.',
    );
    try {
      final title = params['title'] as String? ?? 'Time Up';
      final body = params['body'] as String? ?? 'Service time completed';
      await _showNotificationFromCallback(id, title, body);
      debugPrint('✅ Notification shown despite error');
    } catch (showError) {
      debugPrint('❌ Failed to show notification: $showError');
    }
  }
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

  const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

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
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

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
      final androidImplementation =
          _notifications
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

    debugPrint('📅 Scheduling notification:');
    debugPrint('   Notification ID: $notificationId');
    debugPrint('   Delay: ${delay.inMinutes} minutes (${delay.inSeconds} seconds)');
    debugPrint('   End Time: $endTime');
    debugPrint('   Current Time: ${DateTime.now()}');

    if (delay.isNegative) {
      debugPrint('⚠️ Cannot schedule notification: delay is negative (end time is in the past)');
      return;
    }

    try {
      final scheduled = await AndroidAlarmManager.oneShot(
        delay,
        notificationId,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: false,
        params: {
          'serviceId': serviceId,
          'sessionId': sessionId,
          'serviceType': serviceType,
          'title': 'Time Up: $serviceType',
          'body': '$serviceType session for $customerName has completed',
        },
      );

      if (scheduled) {
        debugPrint('✅ Notification scheduled successfully for $serviceType');
      } else {
        debugPrint('❌ Failed to schedule notification (AndroidAlarmManager returned false)');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error scheduling alarm: $e');
      debugPrint('Stack trace: $stackTrace');
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
    String? serviceType,
  }) async {
    // Check if notifications are enabled for this specific service type
    if (serviceType != null) {
      try {
        final notificationDoc =
            await FirebaseFirestore.instance.collection('settings').doc('notifications').get();
        if (notificationDoc.exists) {
          final data = notificationDoc.data();
          // Map service type to setting key (case-insensitive)
          final serviceTypeLower = serviceType.toLowerCase();
          String settingKey;
          if (serviceTypeLower == 'ps4') {
            settingKey = 'ps4';
          } else if (serviceTypeLower == 'ps5') {
            settingKey = 'ps5';
          } else if (serviceTypeLower == 'vr') {
            settingKey = 'vr';
          } else if (serviceTypeLower == 'simulator') {
            settingKey = 'simulator';
          } else if (serviceTypeLower == 'theatre') {
            settingKey = 'theatre';
          } else {
            // Unknown service type, default to enabled
            settingKey = '';
          }

          if (settingKey.isNotEmpty) {
            final notificationsEnabled = data?[settingKey] ?? true;
            if (!notificationsEnabled) {
              debugPrint(
                'ℹ️ Notifications are disabled for $serviceType. Not showing notification.',
              );
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Could not check notification setting, defaulting to enabled: $e');
        // Default to enabled if check fails
      }
    }

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

    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

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
