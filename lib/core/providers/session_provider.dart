import 'package:flutter/material.dart';
import 'package:rowzow/core/services/session_service.dart';
import 'package:rowzow/core/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
      // Check for booking conflicts before adding service
      await _checkBookingConflict(service);
      
      await _service.addService(activeSessionId!, service);
      await refreshSession();
      
      // Schedule notification for time-up (PS4, PS5, Theatre, Simulator, VR)
      await _scheduleNotificationForService(service, activeSessionId!);
    } catch (e) {
      // Re-throw to let the caller handle it
      rethrow;
    }
  }

  /// Check if the service time conflicts with existing bookings
  Future<void> _checkBookingConflict(Map<String, dynamic> service) async {
    final serviceType = service['type'] as String? ?? '';
    final startTimeStr = service['startTime'] as String?;
    
    if (startTimeStr == null || serviceType.isEmpty) {
      return; // No conflict check needed if no start time or service type
    }

    try {
      final startTime = DateTime.parse(startTimeStr);
      final dateId = DateFormat('yyyy-MM-dd').format(startTime);
      
      // Calculate duration based on service type
      double serviceDurationHours = 0.0;
      
      if (serviceType == 'PS4' || serviceType == 'PS5') {
        final hours = (service['hours'] as num?)?.toInt() ?? 0;
        final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
        serviceDurationHours = hours + (minutes / 60.0);
      } else if (serviceType == 'Theatre') {
        final hours = (service['hours'] as num?)?.toInt() ?? 1;
        serviceDurationHours = hours.toDouble();
      } else if (serviceType == 'Simulator' || serviceType == 'VR') {
        final games = (service['games'] as num?)?.toInt() ?? 1;
        final durationMinutes = games * 5; // 5 minutes per game
        serviceDurationHours = durationMinutes / 60.0;
      }

      if (serviceDurationHours <= 0) {
        return; // No duration, no conflict
      }

      // Get existing bookings for this date and service type
      final bookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('date', isEqualTo: dateId)
          .where('serviceType', isEqualTo: serviceType)
          .get();

      // Check for conflicts
      final serviceStartHour = startTime.hour;
      final serviceStartMinute = startTime.minute;
      final serviceStartDecimal = serviceStartHour + (serviceStartMinute / 60.0);
      final serviceEndDecimal = serviceStartDecimal + serviceDurationHours;

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String? ?? 'pending').toLowerCase().trim();
        
        // IMPORTANT: Check conflicts with 'pending', 'confirmed', and 'done' bookings
        // Only 'cancelled' bookings don't block (time slots are available)
        // Once a booking is made, it blocks the slot regardless of pending/done status
        if (status == 'cancelled') {
          continue; // Skip - don't check for conflicts, allow the service
        }
        // 'pending', 'confirmed', and 'done' bookings will cause conflicts

        final bookedTimeSlot = data['timeSlot'] as String? ?? '';
        if (bookedTimeSlot.isEmpty) continue;

        final bookedDuration = (data['durationHours'] as num?)?.toDouble() ?? 1.0;
        
        // Parse booked time slot (e.g., "14:00")
        final bookedParts = bookedTimeSlot.split(':');
        if (bookedParts.length != 2) continue;
        
        final bookedHour = int.tryParse(bookedParts[0]) ?? 0;
        final bookedStartDecimal = bookedHour.toDouble();
        final bookedEndDecimal = bookedStartDecimal + bookedDuration;

        // Check if service overlaps with booking
        if ((serviceStartDecimal >= bookedStartDecimal && serviceStartDecimal < bookedEndDecimal) ||
            (serviceEndDecimal > bookedStartDecimal && serviceEndDecimal <= bookedEndDecimal) ||
            (serviceStartDecimal <= bookedStartDecimal && serviceEndDecimal >= bookedEndDecimal)) {
          // Format booked end time
          final bookedEndHour = (bookedStartDecimal + bookedDuration).floor();
          final bookedEndMinute = ((bookedStartDecimal + bookedDuration - bookedEndHour) * 60).round();
          final bookedEndTime = '${bookedEndHour.toString().padLeft(2, '0')}:${bookedEndMinute.toString().padLeft(2, '0')}';
          
          // Format service time
          final serviceTimeStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
          
          throw Exception(
            'This time slot conflicts with an existing booking.\n\n'
            'Your service time: $serviceTimeStr (${serviceDurationHours.toStringAsFixed(1)}h)\n'
            'Existing booking: $bookedTimeSlot - $bookedEndTime (${bookedDuration.toStringAsFixed(1)}h)\n\n'
            'Please choose a different time to avoid conflicts.'
          );
        }
      }
    } catch (e) {
      // If it's already our custom exception, re-throw it
      if (e.toString().contains('conflicts with an existing booking')) {
        rethrow;
      }
      // Otherwise, log and continue (don't block service addition for other errors)
      debugPrint('Error checking booking conflict: $e');
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
          // Calculate duration based on games (5 minutes per game)
          final games = (service['games'] as num?)?.toInt() ?? 1;
          final duration = games * 5; // 5 minutes per game
          endTime = startTime.add(Duration(minutes: duration));
        }
      } else if (serviceType == 'VR') {
        final startTimeStr = service['startTime'] as String?;
        if (startTimeStr != null) {
          final startTime = DateTime.parse(startTimeStr);
          // Calculate duration based on games (5 minutes per game)
          final games = (service['games'] as num?)?.toInt() ?? 1;
          final duration = games * 5; // 5 minutes per game
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
    
    // Schedule new notification for updated service (PS4, PS5, Theatre, Simulator, VR)
    await _scheduleNotificationForService(updatedService, activeSessionId!);
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
