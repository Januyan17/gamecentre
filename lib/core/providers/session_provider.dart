import 'package:flutter/material.dart';
import 'package:rowzow/core/services/session_service.dart';
import 'package:rowzow/core/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SessionProvider extends ChangeNotifier {
  final SessionService _service = SessionService();

  String? activeSessionId;
  double currentTotal = 0;
  List<Map<String, dynamic>> services = [];

  /// Reset provider state (called when daily reset happens)
  void resetState() {
    activeSessionId = null;
    currentTotal = 0;
    services = [];
    notifyListeners();
  }

  Future<void> createSession(String name) async {
    activeSessionId = await _service.createSession(name);
    currentTotal = 0;
    services = [];
    notifyListeners();
  }

  Future<void> loadSession(String sessionId) async {
    activeSessionId = sessionId;
    await refreshSession();
  }

  Future<void> refreshSession() async {
    if (activeSessionId == null) return;

    final doc = await _service.sessionsRef().doc(activeSessionId!).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      currentTotal = (data['totalAmount'] ?? 0).toDouble();
      services = List<Map<String, dynamic>>.from(data['services'] ?? []);
      notifyListeners();
    } else {
      // Session might have been closed
      activeSessionId = null;
      currentTotal = 0;
      services = [];
      notifyListeners();
    }
  }

  Future<void> addService(Map<String, dynamic> service) async {
    if (activeSessionId == null) {
      throw Exception('No active session. Please create a session first.');
    }
    try {
      await _service.addService(activeSessionId!, service);
      await refreshSession();
      
      // Schedule notification for time-up (only for PS4, PS5, Theatre, Simulator - not VR)
      final serviceType = service['type'] as String? ?? '';
      if (serviceType != 'VR') {
        await _scheduleNotificationForService(service, activeSessionId!);
      }
    } catch (e) {
      // Re-throw to let the caller handle it
      rethrow;
    }
  }

  /// Schedule a notification for when a service time slot completes
  Future<void> _scheduleNotificationForService(
    Map<String, dynamic> service,
    String sessionId,
  ) async {
    try {
      // Get customer name from session
      final sessionDoc = await _service.sessionsRef().doc(sessionId).get();
      final sessionData = sessionDoc.data() as Map<String, dynamic>?;
      final customerName = sessionData?['customerName'] as String? ?? 'Customer';

      final serviceType = service['type'] as String? ?? '';
      final serviceId = service['id'] as String? ?? '${sessionId}_${DateTime.now().millisecondsSinceEpoch}';

      DateTime? endTime;

      // Calculate end time based on service type
      if (serviceType == 'PS4' || serviceType == 'PS5') {
        final startTimeStr = service['startTime'] as String?;
        if (startTimeStr != null) {
          final startTime = DateTime.parse(startTimeStr);
          final hours = (service['hours'] as num?)?.toInt() ?? 0;
          final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
          endTime = startTime.add(Duration(hours: hours, minutes: minutes));
        }
      } else if (serviceType == 'Theatre') {
        final startTimeStr = service['startTime'] as String?;
        if (startTimeStr != null) {
          final startTime = DateTime.parse(startTimeStr);
          final hours = (service['hours'] as num?)?.toInt() ?? 1;
          endTime = startTime.add(Duration(hours: hours));
        }
      } else if (serviceType == 'Simulator') {
        final startTimeStr = service['startTime'] as String?;
        if (startTimeStr != null) {
          final startTime = DateTime.parse(startTimeStr);
          final duration = (service['duration'] as num?)?.toInt() ?? 30;
          endTime = startTime.add(Duration(minutes: duration));
        }
      }

      // Schedule notification if end time is calculated
      if (endTime != null) {
        debugPrint('Attempting to schedule notification:');
        debugPrint('  Service Type: $serviceType');
        debugPrint('  Service ID: $serviceId');
        debugPrint('  Start Time: ${service['startTime']}');
        debugPrint('  End Time: $endTime');
        debugPrint('  Current Time: ${DateTime.now()}');
        
        await NotificationService().scheduleServiceTimeUpNotification(
          serviceId: serviceId,
          serviceType: serviceType,
          customerName: customerName,
          endTime: endTime,
          sessionId: activeSessionId!,
        );
        
        debugPrint('✅ Notification scheduling completed for $serviceType');
      } else {
        debugPrint('⚠️ Cannot schedule notification: endTime is null');
        debugPrint('  Service Type: $serviceType');
        debugPrint('  Service Data: $service');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error scheduling notification: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't throw - notification failure shouldn't break service addition
    }
  }

  Future<void> updateService(
    int index,
    Map<String, dynamic> updatedService,
  ) async {
    if (activeSessionId == null) return;
    
    // Cancel old notification if service exists
    if (index < services.length) {
      final oldService = services[index];
      final oldServiceId = oldService['id'] as String?;
      if (oldServiceId != null) {
        await NotificationService().cancelNotification(oldServiceId);
      }
    }
    
    await _service.updateService(activeSessionId!, index, updatedService);
    await refreshSession();
    
    // Schedule new notification for updated service (only for PS4, PS5, Theatre, Simulator - not VR)
    final serviceType = updatedService['type'] as String? ?? '';
    if (serviceType != 'VR') {
      await _scheduleNotificationForService(updatedService, activeSessionId!);
    }
  }

  Future<void> deleteService(int index) async {
    if (activeSessionId == null) return;
    
    // Cancel notification for the deleted service
    if (index < services.length) {
      final service = services[index];
      final serviceId = service['id'] as String?;
      if (serviceId != null) {
        await NotificationService().cancelNotification(serviceId);
      }
    }
    
    await _service.deleteService(activeSessionId!, index);
    await refreshSession();
  }

  Future<void> applyDiscount(double discountAmount) async {
    if (activeSessionId == null) return;
    await _service.applyDiscount(activeSessionId!, discountAmount);
    await refreshSession();
  }

  Future<void> removeDiscount() async {
    if (activeSessionId == null) return;
    await _service.removeDiscount(activeSessionId!);
    await refreshSession();
  }

  Future<void> closeSession() async {
    if (activeSessionId == null) return;
    
    // Cancel all notifications for all services in this session BEFORE closing
    for (var service in services) {
      final serviceId = service['id'] as String?;
      if (serviceId != null) {
        await NotificationService().cancelNotification(serviceId);
      }
    }
    
    // Get the final amount (with discount if applied)
    final doc = await _service.sessionsRef().doc(activeSessionId!).get();
    double finalTotal = currentTotal;
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      finalTotal = (data?['finalAmount'] ?? data?['totalAmount'] ?? currentTotal).toDouble();
    }
    
    await _service.closeSession(activeSessionId!, finalTotal);
    activeSessionId = null;
    currentTotal = 0;
    services = [];
    notifyListeners();
  }

  Future<void> deleteActiveSession(String sessionId) async {
    // Cancel all notifications for all services in this session BEFORE deleting
    if (activeSessionId == sessionId) {
      for (var service in services) {
        final serviceId = service['id'] as String?;
        if (serviceId != null) {
          await NotificationService().cancelNotification(serviceId);
        }
      }
    }
    
    await _service.deleteActiveSession(sessionId);
    // If the deleted session was the active one, clear it
    if (activeSessionId == sessionId) {
      activeSessionId = null;
      currentTotal = 0;
      services = [];
      notifyListeners();
    }
  }

  CollectionReference sessionsRef() => _service.sessionsRef();
}
