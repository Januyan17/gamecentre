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

  /// Get price per person for VR/Simulator
  /// Each person gets 1 game (5 minutes)
  /// Returns the price for one person (1 game)
  static Future<double> getPricePerPerson({
    required String deviceType,
  }) async {
    if (deviceType != 'VR' && deviceType != 'Simulator') {
      throw Exception('getPricePerPerson is only for VR and Simulator');
    }

    // 1 game per person = 5 minutes
    // For VR: price per game = price per person (from admin settings)
    // For Simulator: price per game = price per person (from admin settings)
    if (deviceType == 'VR') {
      // VR price per game = price per person
      return await PriceCalculator.vr();
    } else {
      // Simulator: 1 game per person
      return await PriceCalculator.carSimulator();
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
            break; // Only add session once
          }
        }
      }

      return matchingSessions;
    } catch (e) {
      debugPrint('Error getting active sessions: $e');
      return [];
    }
  }

  /// Check if a time slot has conflicts with existing bookings or active sessions
  static Future<bool> hasTimeConflict({
    required String deviceType,
    required String date,
    required String timeSlot,
    required double durationHours,
  }) async {
    try {
      // Parse time slot (format: "HH:MM")
      final timeParts = timeSlot.split(':');
      if (timeParts.length != 2) {
        debugPrint('Invalid time slot format: $timeSlot');
        return false;
      }

      final startHour = int.tryParse(timeParts[0]) ?? 0;
      final startMinute = int.tryParse(timeParts[1]) ?? 0;
      final startDecimal = startHour + (startMinute / 60.0);
      final endDecimal = startDecimal + durationHours;

      // Check bookings collection
      final bookingsSnapshot = await _firestore
          .collection('bookings')
          .where('date', isEqualTo: date)
          .where('serviceType', isEqualTo: deviceType)
          .get();

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String? ?? 'pending').toLowerCase().trim();
        if (status == 'cancelled') continue;

        final bookingTimeSlot = data['timeSlot'] as String? ?? '';
        if (bookingTimeSlot.isEmpty) continue;

        final bookingTimeParts = bookingTimeSlot.split(':');
        if (bookingTimeParts.length != 2) continue;

        final bookingStartHour = int.tryParse(bookingTimeParts[0]) ?? 0;
        final bookingStartMinute = int.tryParse(bookingTimeParts[1]) ?? 0;
        final bookingStartDecimal = bookingStartHour + (bookingStartMinute / 60.0);
        final bookingDurationHours = (data['durationHours'] as num?)?.toDouble() ?? 1.0;
        final bookingEndDecimal = bookingStartDecimal + bookingDurationHours;

        // Check for overlap
        if ((startDecimal < bookingEndDecimal && endDecimal > bookingStartDecimal)) {
          return true; // Conflict found
        }
      }

      // Check if date is in the past
      final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isPastDate = date.compareTo(todayId) < 0;

      // Check active sessions (for today/future dates)
      if (!isPastDate) {
        final activeSessionsSnapshot = await _firestore
            .collection('active_sessions')
            .where('status', isEqualTo: 'active')
            .get();

        for (var sessionDoc in activeSessionsSnapshot.docs) {
          final sessionData = sessionDoc.data();
          final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

          for (var service in services) {
            final serviceType = service['type'] as String? ?? '';
            if (serviceType != deviceType) continue;

            final startTimeStr = service['startTime'] as String? ?? '';
            if (startTimeStr.isEmpty) continue;

            try {
              final startTime = DateTime.parse(startTimeStr);
              final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);
              if (serviceDateId != date) continue;

              final hours = (service['hours'] as num?)?.toInt() ?? 0;
              final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
              final serviceDurationHours = hours + (minutes / 60.0);

              final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
              final serviceEndDecimal = serviceStartDecimal + serviceDurationHours;

              // Check for overlap
              if ((startDecimal < serviceEndDecimal && endDecimal > serviceStartDecimal)) {
                return true; // Conflict found
              }
            } catch (e) {
              debugPrint('Error parsing session time: $e');
              continue;
            }
          }
        }

        // Also check closed sessions for today's date
        // This ensures completed sessions today remain marked as unavailable
        try {
          if (date == todayId) {
            final historySessionsSnapshot = await _firestore
                .collection('days')
                .doc(date)
                .collection('sessions')
                .where('status', isEqualTo: 'closed')
                .get();

            for (var sessionDoc in historySessionsSnapshot.docs) {
              final sessionData = sessionDoc.data();
              final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

              for (var service in services) {
                final serviceType = service['type'] as String? ?? '';
                if (serviceType != deviceType) continue;

                final startTimeStr = service['startTime'] as String? ?? '';
                if (startTimeStr.isEmpty) continue;

                try {
                  final startTime = DateTime.parse(startTimeStr);
                  final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);
                  if (serviceDateId != date) continue;

                  final hours = (service['hours'] as num?)?.toInt() ?? 0;
                  final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                  final serviceDurationHours = hours + (minutes / 60.0);

                  final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
                  final serviceEndDecimal = serviceStartDecimal + serviceDurationHours;

                  // Check for overlap
                  if ((startDecimal < serviceEndDecimal && endDecimal > serviceStartDecimal)) {
                    return true; // Conflict found
                  }
                } catch (e) {
                  debugPrint('Error parsing closed session time: $e');
                  continue;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error checking closed sessions for today: $e');
        }
      } else {
        // For past dates, also check history sessions (closed/ended sessions)
        // This ensures past bookings remain marked as unavailable for historical tracking
        try {
          final historySessionsSnapshot = await _firestore
              .collection('days')
              .doc(date)
              .collection('sessions')
              .where('status', isEqualTo: 'closed')
              .get();

          for (var sessionDoc in historySessionsSnapshot.docs) {
            final sessionData = sessionDoc.data();
            final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

            for (var service in services) {
              final serviceType = service['type'] as String? ?? '';
              if (serviceType != deviceType) continue;

              final startTimeStr = service['startTime'] as String? ?? '';
              if (startTimeStr.isEmpty) continue;

              try {
                final startTime = DateTime.parse(startTimeStr);
                final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);
                if (serviceDateId != date) continue;

                final hours = (service['hours'] as num?)?.toInt() ?? 0;
                final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                final serviceDurationHours = hours + (minutes / 60.0);

                final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
                final serviceEndDecimal = serviceStartDecimal + serviceDurationHours;

                // Check for overlap
                if ((startDecimal < serviceEndDecimal && endDecimal > serviceStartDecimal)) {
                  return true; // Conflict found
                }
              } catch (e) {
                debugPrint('Error parsing history session time: $e');
                continue;
              }
            }
          }
        } catch (e) {
          debugPrint('Error checking history sessions: $e');
        }
      }

      return false; // No conflicts
    } catch (e) {
      debugPrint('Error checking time conflict: $e');
      return false; // On error, assume no conflict
    }
  }

  /// Validate booking data
  static void validateBookingData({
    required String customerName,
    String? phoneNumber,
    required String serviceType,
  }) {
    if (customerName.trim().isEmpty) {
      throw Exception('Customer name is required');
    }

    if (customerName.trim().length < 2) {
      throw Exception('Customer name must be at least 2 characters');
    }

    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      final phoneDigits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (phoneDigits.length < 7 || phoneDigits.length > 15) {
        throw Exception('Phone number must be 7-15 digits');
      }
    }
  }
}
