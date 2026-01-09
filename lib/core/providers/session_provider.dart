import 'package:flutter/material.dart';
import 'package:rowzow/core/services/session_service.dart';
import 'package:rowzow/core/services/notification_service.dart';
import 'package:rowzow/core/services/device_capacity_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SessionProvider extends ChangeNotifier {
  final SessionService _service = SessionService();

  String? activeSessionId;
  double currentTotal = 0;
  List<Map<String, dynamic>> services = [];

  // Helper function to convert 24-hour time string to 12-hour format
  String _formatTime12Hour(String time24Hour) {
    try {
      final parts = time24Hour.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = parts.length > 1 ? parts[1] : '00';
        final period = hour >= 12 ? 'PM' : 'AM';
        final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '$hour12:${minute.padLeft(2, '0')} $period';
      }
    } catch (e) {
      // If parsing fails, return original
    }
    return time24Hour;
  }

  /// Reset provider state (called when daily reset happens)
  void resetState() {
    activeSessionId = null;
    currentTotal = 0;
    services = [];
    notifyListeners();
  }

  Future<void> createSession(String name, {String? phoneNumber}) async {
    activeSessionId = await _service.createSession(name, phoneNumber: phoneNumber);
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
      
      // Store the startTime to find the service after refresh
      final startTimeStr = service['startTime'] as String?;
      final serviceType = service['type'] as String? ?? '';
      
      await _service.addService(activeSessionId!, service);
      await refreshSession();
      
      // After refresh, find the service that was just added from Firestore
      // This ensures we use the correct service ID that was actually saved
      Map<String, dynamic>? savedService;
      if (startTimeStr != null && services.isNotEmpty) {
        try {
          savedService = services.firstWhere(
            (s) {
              final sType = s['type'] as String?;
              final sStartTime = s['startTime'] as String?;
              return sType == serviceType && sStartTime == startTimeStr;
            },
            orElse: () => service, // Fallback to original if not found
          );
          debugPrint('✅ Found saved service in Firestore for notification scheduling');
        } catch (e) {
          debugPrint('⚠️ Could not find saved service, using original: $e');
          savedService = service; // Fallback to original service
        }
      } else {
        savedService = service; // Fallback to original service
      }
      
      // Schedule notification for time-up (PS4, PS5, Theatre, Simulator, VR)
      // Use the service from Firestore to ensure correct ID
      await _scheduleNotificationForService(savedService, activeSessionId!);
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

      // Check device capacity first
      final capacity = await DeviceCapacityService.getDeviceCapacity(serviceType);
      
      if (capacity > 0) {
        // Use capacity-based checking: check if there are available slots
        final serviceTime24Hour = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
        final availableSlots = await DeviceCapacityService.getAvailableSlots(
          deviceType: serviceType,
          date: dateId,
          timeSlot: serviceTime24Hour,
          durationHours: serviceDurationHours,
        );

        // Allow service addition if there's at least 1 slot available
        if (availableSlots <= 0 && availableSlots != -1) {
          // No slots available
          final serviceTimeStr = DateFormat('hh:mm a').format(startTime);
          final serviceEndTime = startTime.add(Duration(
            hours: serviceDurationHours.floor(),
            minutes: ((serviceDurationHours - serviceDurationHours.floor()) * 60).round(),
          ));
          final serviceEndTimeStr = DateFormat('hh:mm a').format(serviceEndTime);
          
          throw Exception(
            'Cannot add service: All $capacity $serviceType slots are fully booked at this time.\n\n'
            'Your service time: $serviceTimeStr - $serviceEndTimeStr (${serviceDurationHours.toStringAsFixed(1)}h)\n'
            'Available slots: 0 of $capacity\n\n'
            'Please wait until a slot becomes available or choose a different time.'
          );
        }
        // If availableSlots > 0 or -1 (unlimited), allow service addition
      } else {
        // Capacity is 0 (unlimited) - use old overlap-based checking for backward compatibility
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
            // Format booked end time in 12-hour format
            final bookedEndHour = (bookedStartDecimal + bookedDuration).floor();
            final bookedEndMinute = ((bookedStartDecimal + bookedDuration - bookedEndHour) * 60).round();
            final bookedEndTime24Hour = '${bookedEndHour.toString().padLeft(2, '0')}:${bookedEndMinute.toString().padLeft(2, '0')}';
            final bookedEndTime = _formatTime12Hour(bookedEndTime24Hour);
            
            // Format service time in 12-hour format
            final serviceTimeStr = DateFormat('hh:mm a').format(startTime);
            
            // Format booked time slot in 12-hour format
            final bookedTime12Hour = _formatTime12Hour(bookedTimeSlot);
            
            throw Exception(
              'This time slot conflicts with an existing booking.\n\n'
              'Your service time: $serviceTimeStr (${serviceDurationHours.toStringAsFixed(1)}h)\n'
              'Existing booking: $bookedTime12Hour - $bookedEndTime (${bookedDuration.toStringAsFixed(1)}h)\n\n'
              'Please choose a different time to avoid conflicts.'
            );
          }
        }
      }
    } catch (e) {
      // If it's already our custom exception, re-throw it
      if (e.toString().contains('conflicts with an existing booking') ||
          e.toString().contains('Cannot add service')) {
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
      
      // Get service ID - ALWAYS try to get it from Firestore first to ensure it matches
      // This is critical because the service object passed in might have a different ID
      String? serviceId;
      final services = List<Map<String, dynamic>>.from(sessionData?['services'] ?? []);
      final startTimeStr = service['startTime'] as String?;
      
      if (startTimeStr != null && services.isNotEmpty) {
        // Find the service in Firestore that matches this service
        // Match by type and startTime to get the correct ID from Firestore
        try {
          final matchingService = services.firstWhere(
            (s) {
              final sType = s['type'] as String?;
              final sStartTime = s['startTime'] as String?;
              return sType == serviceType && sStartTime == startTimeStr;
            },
          );
          serviceId = matchingService['id'] as String?;
          if (serviceId != null && serviceId.isNotEmpty) {
            debugPrint('✅ Found service ID from Firestore: $serviceId');
          }
        } catch (e) {
          debugPrint('⚠️ Could not find matching service in Firestore: $e');
          debugPrint('   Looking for: type=$serviceType, startTime=$startTimeStr');
          debugPrint('   Available services: ${services.map((s) => '${s['type']}@${s['startTime']}').join(', ')}');
        }
      }
      
      // Fallback: try to get ID from service object
      if (serviceId == null || serviceId.isEmpty) {
        serviceId = service['id'] as String?;
        if (serviceId != null && serviceId.isNotEmpty) {
          debugPrint('📋 Using service ID from service object: $serviceId');
        }
      }
      
      // Last resort: generate one (but this should rarely happen and might cause issues)
      if (serviceId == null || serviceId.isEmpty) {
        serviceId = '${sessionId}_${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('⚠️ Generated fallback service ID: $serviceId (WARNING: May not match Firestore)');
      }
      
      debugPrint('📋 Scheduling notification for service:');
      debugPrint('   Service Type: $serviceType');
      debugPrint('   Service ID: $serviceId');
      debugPrint('   Session ID: $sessionId');
      debugPrint('   Service has ID in object: ${service['id'] != null}');
      debugPrint('   Services in Firestore: ${services.length}');

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
    
    // Clear slot availability cache when session is closed
    // This ensures slots are immediately freed up for new bookings
    DeviceCapacityService.clearCapacityCache();
    
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
