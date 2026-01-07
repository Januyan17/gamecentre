import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'price_calculator.dart';

/// Centralized service for all booking-related logic.
/// This includes pricing calculations, time extensions, controller add-ons,
/// and validation logic that should be reused across the app.
class BookingLogicService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Calculate price for a device booking
  /// Supports PS4, PS5, VR, Simulator, and Theatre
  static Future<double> calculateBookingPrice({
    required String deviceType,
    required int hours,
    required int minutes,
    int additionalControllers = 0,
    int? people, // For Theatre
  }) async {
    switch (deviceType) {
      case 'PS4':
        return await PriceCalculator.ps4Price(
          hours: hours,
          minutes: minutes,
          additionalControllers: additionalControllers,
        );
      case 'PS5':
        return await PriceCalculator.ps5Price(
          hours: hours,
          minutes: minutes,
          additionalControllers: additionalControllers,
        );
      case 'VR':
        final durationMinutes = (hours * 60) + minutes;
        final games = (durationMinutes / 5).ceil();
        final slots = (games / 2).ceil();
        final pricePerSlot = await PriceCalculator.vr();
        return pricePerSlot * slots;
      case 'Simulator':
        final durationMinutes = (hours * 60) + minutes;
        final games = (durationMinutes / 5).ceil();
        final pricePerGame = await PriceCalculator.carSimulator();
        return pricePerGame * games;
      case 'Theatre':
        if (people == null) {
          throw Exception('Number of people is required for Theatre booking');
        }
        return await PriceCalculator.theatre(
          hours: hours,
          people: people,
        );
      default:
        throw Exception('Unsupported device type: $deviceType');
    }
  }

  /// Calculate price for extending time on an active session
  /// Uses the same pricing logic as new bookings
  static Future<double> calculateTimeExtensionPrice({
    required String deviceType,
    required int additionalHours,
    required int additionalMinutes,
    int additionalControllers = 0,
    int? people, // For Theatre
  }) async {
    return await calculateBookingPrice(
      deviceType: deviceType,
      hours: additionalHours,
      minutes: additionalMinutes,
      additionalControllers: additionalControllers,
      people: people,
    );
  }

  /// Calculate price for adding controllers to an existing session
  static Future<double> calculateControllerAddOnPrice({
    required String deviceType,
    required int currentHours,
    required int currentMinutes,
    required int additionalControllers,
  }) async {
    if (deviceType != 'PS4' && deviceType != 'PS5') {
      throw Exception('Controllers can only be added to PS4/PS5 sessions');
    }

    final controllerPrice = await PriceCalculator.getAdditionalControllerPrice();
    
    // Calculate total duration in hours (including partial hours)
    final totalHours = currentHours + (currentMinutes / 60.0);
    
    // Price = controller price × number of controllers × total hours
    return controllerPrice * additionalControllers * totalHours;
  }

  /// Check if a device has an active session
  /// Returns the session ID if found, null otherwise
  static Future<String?> getActiveSessionForDevice({
    required String deviceType,
  }) async {
    try {
      final activeSessions = await _firestore
          .collection('active_sessions')
          .where('status', isEqualTo: 'active')
          .get();

      for (var sessionDoc in activeSessions.docs) {
        final sessionData = sessionDoc.data();
        final services = List<Map<String, dynamic>>.from(
          sessionData['services'] ?? [],
        );

        // Check if any service in this session matches the device type
        for (var service in services) {
          final serviceType = service['type'] as String? ?? '';
          if (serviceType == deviceType) {
            return sessionDoc.id;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error checking active session: $e');
      return null;
    }
  }

  /// Get all active sessions for a specific device type
  /// Returns a list of session IDs
  static Future<List<Map<String, dynamic>>> getActiveSessionsForDevice({
    required String deviceType,
  }) async {
    try {
      final activeSessions = await _firestore
          .collection('active_sessions')
          .where('status', isEqualTo: 'active')
          .get();

      final List<Map<String, dynamic>> matchingSessions = [];

      for (var sessionDoc in activeSessions.docs) {
        final sessionData = sessionDoc.data();
        final services = List<Map<String, dynamic>>.from(
          sessionData['services'] ?? [],
        );

        // Check if any service in this session matches the device type
        for (var service in services) {
          final serviceType = service['type'] as String? ?? '';
          if (serviceType == deviceType) {
            matchingSessions.add({
              'sessionId': sessionDoc.id,
              'sessionData': sessionData,
              'service': service,
            });
            break; // Only add session once even if multiple services match
          }
        }
      }

      return matchingSessions;
    } catch (e) {
      debugPrint('Error getting active sessions: $e');
      return [];
    }
  }

  /// Check if a time slot conflicts with existing bookings or active sessions
  static Future<bool> hasTimeConflict({
    required String deviceType,
    required String date,
    required String timeSlot,
    required double durationHours,
  }) async {
    try {
      final dateId = date; // Assuming date is already in yyyy-MM-dd format
      final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isPastDate = dateId.compareTo(todayId) < 0;

      // Parse time slot
      final timeParts = timeSlot.split(':');
      if (timeParts.length < 2) return false;
      final selectedHour = int.tryParse(timeParts[0]) ?? 0;
      final selectedMinute = int.tryParse(timeParts[1]) ?? 0;
      final selectedStartDecimal = selectedHour + (selectedMinute / 60.0);
      final selectedEndDecimal = selectedStartDecimal + durationHours;

      // Check bookings collection (for today and future dates)
      if (!isPastDate) {
        final bookings = await _firestore
            .collection('bookings')
            .where('date', isEqualTo: dateId)
            .where('serviceType', isEqualTo: deviceType)
            .get();

        for (var doc in bookings.docs) {
          final data = doc.data();
          final status = (data['status'] as String? ?? 'pending').toLowerCase();
          if (status == 'cancelled') continue;

          final bookedTimeSlot = data['timeSlot'] as String? ?? '';
          if (bookedTimeSlot.isEmpty) continue;

          final bookedParts = bookedTimeSlot.split(':');
          final bookedHour = bookedParts.length == 2
              ? int.tryParse(bookedParts[0]) ?? 0
              : 0;
          final bookedMinute = bookedParts.length == 2
              ? int.tryParse(bookedParts[1]) ?? 0
              : 0;
          final bookedDuration =
              (data['durationHours'] as num?)?.toDouble() ?? 1.0;

          final bookedStartDecimal = bookedHour + (bookedMinute / 60.0);
          final bookedEndDecimal = bookedStartDecimal + bookedDuration;

          // Check for overlap
          if ((selectedStartDecimal >= bookedStartDecimal &&
                  selectedStartDecimal < bookedEndDecimal) ||
              (selectedEndDecimal > bookedStartDecimal &&
                  selectedEndDecimal <= bookedEndDecimal) ||
              (selectedStartDecimal <= bookedStartDecimal &&
                  selectedEndDecimal >= bookedEndDecimal)) {
            return true; // Conflict found
          }
        }
      }

      // Check active sessions (for any date, as sessions can span dates)
      final activeSessions = await _firestore
          .collection('active_sessions')
          .where('status', isEqualTo: 'active')
          .get();

      for (var sessionDoc in activeSessions.docs) {
        final sessionData = sessionDoc.data();
        final services = List<Map<String, dynamic>>.from(
          sessionData['services'] ?? [],
        );

        for (var service in services) {
          final serviceType = service['type'] as String? ?? '';
          if (serviceType != deviceType) continue;

          final startTimeStr = service['startTime'] as String?;
          if (startTimeStr == null) continue;

          try {
            final startTime = DateTime.parse(startTimeStr);
            final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);
            
            // Only check conflicts for the same date
            if (serviceDateId != dateId) continue;

            final hours = (service['hours'] as num?)?.toInt() ?? 0;
            final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
            final serviceDuration = hours + (minutes / 60.0);

            final serviceStartDecimal =
                startTime.hour + (startTime.minute / 60.0);
            final serviceEndDecimal = serviceStartDecimal + serviceDuration;

            // Check for overlap
            if ((selectedStartDecimal >= serviceStartDecimal &&
                    selectedStartDecimal < serviceEndDecimal) ||
                (selectedEndDecimal > serviceStartDecimal &&
                    selectedEndDecimal <= serviceEndDecimal) ||
                (selectedStartDecimal <= serviceStartDecimal &&
                    selectedEndDecimal >= serviceEndDecimal)) {
              return true; // Conflict found
            }
          } catch (e) {
            debugPrint('Error parsing service start time: $e');
            continue;
          }
        }
      }

      return false; // No conflict
    } catch (e) {
      debugPrint('Error checking time conflict: $e');
      return false; // Assume no conflict on error
    }
  }

  /// Validate booking data before creation
  static void validateBookingData({
    required String deviceType,
    required int hours,
    required int minutes,
    required String customerName,
    required String timeSlot,
    int? people, // For Theatre
  }) {
    if (deviceType.isEmpty) {
      throw Exception('Device type is required');
    }
    if (customerName.trim().isEmpty) {
      throw Exception('Customer name is required');
    }
    if (timeSlot.isEmpty) {
      throw Exception('Time slot is required');
    }
    if (hours < 0 || minutes < 0) {
      throw Exception('Duration must be positive');
    }
    if (hours == 0 && minutes == 0) {
      throw Exception('Duration must be greater than 0');
    }

    // Device-specific validations
    if (deviceType == 'Theatre') {
      if (people == null || people <= 0) {
        throw Exception('Number of people must be greater than 0 for Theatre');
      }
    }
  }
}

