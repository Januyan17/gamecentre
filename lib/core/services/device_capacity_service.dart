import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

/// Service for managing device capacity and slot allocation
/// Handles capacity checks, slot counting, and automatic slot assignment
class DeviceCapacityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache for device capacity (similar to PriceCalculator)
  static Map<String, int>? _cachedCapacity;
  static DateTime? _capacityCacheTime;
  static const Duration _capacityCacheDuration = Duration(minutes: 5);
  
  // Cache for available slots per time slot
  static Map<String, int>? _cachedAvailableSlots;
  static DateTime? _slotsCacheTime;
  static const Duration _slotsCacheDuration = Duration(seconds: 30); // Shorter cache for slots as they change frequently

  /// Get device capacity from settings (with caching)
  /// Returns the number of available units for a device type
  static Future<int> getDeviceCapacity(String deviceType) async {
    try {
      // Check cache first
      if (_cachedCapacity != null && 
          _capacityCacheTime != null &&
          DateTime.now().difference(_capacityCacheTime!) < _capacityCacheDuration) {
        final capacityField = _getCapacityFieldName(deviceType);
        return _cachedCapacity![capacityField] ?? 0;
      }
      
      // Fetch from Firestore
      final doc = await _firestore.collection('settings').doc('device_capacity').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Update cache
        _cachedCapacity = {};
        _cachedCapacity!['ps5Count'] = (data['ps5Count'] ?? 0) as int;
        _cachedCapacity!['ps4Count'] = (data['ps4Count'] ?? 0) as int;
        _cachedCapacity!['vrCount'] = (data['vrCount'] ?? 0) as int;
        _cachedCapacity!['simulatorCount'] = (data['simulatorCount'] ?? 0) as int;
        _capacityCacheTime = DateTime.now();
        
        // Map device types to their capacity field names
        final capacityField = _getCapacityFieldName(deviceType);
        return _cachedCapacity![capacityField] ?? 0;
      }
      
      // Update cache with defaults
      _cachedCapacity = {
        'ps5Count': 0,
        'ps4Count': 0,
        'vrCount': 0,
        'simulatorCount': 0,
      };
      _capacityCacheTime = DateTime.now();
      return 0; // Default to 0 if not configured
    } catch (e) {
      debugPrint('Error getting device capacity: $e');
      return 0;
    }
  }
  
  /// Clear capacity cache (call this when capacity is updated)
  static void clearCapacityCache() {
    _cachedCapacity = null;
    _capacityCacheTime = null;
    _cachedAvailableSlots = null;
    _slotsCacheTime = null;
  }

  /// Get capacity field name for device type
  static String _getCapacityFieldName(String deviceType) {
    switch (deviceType.toUpperCase()) {
      case 'PS5':
        return 'ps5Count';
      case 'PS4':
        return 'ps4Count';
      case 'VR':
        return 'vrCount';
      case 'SIMULATOR':
        return 'simulatorCount';
      default:
        return '${deviceType.toLowerCase()}Count';
    }
  }

  /// Count how many slots are occupied for a given date, time, and device type
  /// Considers: pending bookings, active sessions, and closed sessions (for today)
  static Future<int> countOccupiedSlots({
    required String deviceType,
    required String date,
    required String timeSlot,
    required double durationHours,
  }) async {
    try {
      int occupiedCount = 0;

      // Parse time slot
      final timeParts = timeSlot.split(':');
      if (timeParts.length != 2) return 0;

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

        // Check for overlap: Two time ranges overlap if:
        // - The start of one is before the end of the other, AND
        // - The end of one is after the start of the other
        // This means they share some common time period
        final hasOverlap = (startDecimal < bookingEndDecimal && endDecimal > bookingStartDecimal);
        
        // Only count if there's actual overlap (they share time)
        if (hasOverlap) {
          // Count based on service type
          int slotCount = 1;
          if (deviceType == 'PS4' || deviceType == 'PS5') {
            // For PS4/PS5, count the consoleCount (number of consoles booked)
            slotCount = (data['consoleCount'] as num?)?.toInt() ?? 1;
          } else if (deviceType == 'Theatre') {
            // For Theatre, count the totalPeople (number of people booked)
            slotCount = (data['totalPeople'] as num?)?.toInt() ?? 1;
          } else if (deviceType == 'VR' || deviceType == 'Simulator') {
            // For VR/Simulator, count as 1 slot (multiple people can use same slot)
            slotCount = 1;
          }
          occupiedCount += slotCount;
        }
      }

      // Check if date is in the past (needed for converted bookings check)
      final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isPastDate = date.compareTo(todayId) < 0;

      // IMPORTANT: Also check booking_history for converted bookings (for today/future dates)
      // When a booking is converted to active session, it's moved to booking_history with status 'converted_to_session'
      // We need to block the original booking time slots even after conversion
      if (!isPastDate) {
        try {
          final convertedBookingsSnapshot = await _firestore
              .collection('booking_history')
              .where('date', isEqualTo: date)
              .where('serviceType', isEqualTo: deviceType)
              .where('status', isEqualTo: 'converted_to_session')
              .get();

          for (var doc in convertedBookingsSnapshot.docs) {
            final data = doc.data();
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
            final hasOverlap = (startDecimal < bookingEndDecimal && endDecimal > bookingStartDecimal);
            
            if (hasOverlap) {
              // Count based on service type
              int slotCount = 1;
              if (deviceType == 'PS4' || deviceType == 'PS5') {
                // For PS4/PS5, count the consoleCount (number of consoles booked)
                slotCount = (data['consoleCount'] as num?)?.toInt() ?? 1;
              } else if (deviceType == 'Theatre') {
                // For Theatre, count the totalPeople (number of people booked)
                slotCount = (data['totalPeople'] as num?)?.toInt() ?? 1;
              } else if (deviceType == 'VR' || deviceType == 'Simulator') {
                // For VR/Simulator, count as 1 slot (multiple people can use same slot)
                slotCount = 1;
              }
              occupiedCount += slotCount;
            }
          }
        } catch (e) {
          debugPrint('Error checking converted bookings: $e');
        }
      }

      // Check active sessions (for today/future dates)
      // Note: isPastDate is already declared above
      if (!isPastDate) {
        final activeSessionsSnapshot = await _firestore
            .collection('active_sessions')
            .where('status', isEqualTo: 'active')
            .get();

        for (var sessionDoc in activeSessionsSnapshot.docs) {
          final sessionData = sessionDoc.data();
          final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

          // IMPORTANT: Check if this session has a bookingTimeSlot (converted from booking)
          // If yes, block the original booking time slots, not just the actual session start time
          final bookingTimeSlot = sessionData['bookingTimeSlot'] as String? ?? '';
          final bookingDate = sessionData['bookingDate'] as String? ?? '';
          
          if (bookingTimeSlot.isNotEmpty && bookingDate == date) {
            // This session was converted from a booking - block original booking time slots
            // CRITICAL: Only block if the booking's service type matches the device type being checked
            try {
              // Try to get duration and service type from booking history
              final bookingId = sessionData['bookingId'] as String?;
              double bookingDurationHours = 1.0; // Default
              String? bookingServiceType;
              
              if (bookingId != null) {
                try {
                  final bookingDoc = await _firestore
                      .collection('booking_history')
                      .doc(bookingId)
                      .get();
                  if (bookingDoc.exists) {
                    final bookingData = bookingDoc.data();
                    bookingDurationHours = (bookingData?['durationHours'] as num?)?.toDouble() ?? 1.0;
                    bookingServiceType = bookingData?['serviceType'] as String?;
                  }
                } catch (e) {
                  debugPrint('Error getting booking details: $e');
                }
              }

              // CRITICAL: Only block slots if the booking's service type matches the device type
              // This ensures Theatre bookings don't block PS5/PS4/VR/Simulator slots and vice versa
              if (bookingServiceType != null && bookingServiceType.trim() != deviceType.trim()) {
                // Skip this booking - different service type, don't block slots
                // Continue to next iteration to check other services in the session
              } else {
                // Parse booking time slot
                final bookingTimeParts = bookingTimeSlot.split(':');
                if (bookingTimeParts.length == 2) {
                  final bookingStartHour = int.tryParse(bookingTimeParts[0]) ?? 0;
                  final bookingStartMinute = int.tryParse(bookingTimeParts[1]) ?? 0;
                  final bookingStartDecimal = bookingStartHour + (bookingStartMinute / 60.0);
                  final bookingEndDecimal = bookingStartDecimal + bookingDurationHours;

                  // Check for overlap with original booking time slots
                  final hasOverlap = (startDecimal < bookingEndDecimal && endDecimal > bookingStartDecimal);
                  if (hasOverlap) {
                    // Get slot count from booking history based on service type
                    int slotCount = 1;
                    if (bookingId != null) {
                      try {
                        final bookingDoc = await _firestore
                            .collection('booking_history')
                            .doc(bookingId)
                            .get();
                        if (bookingDoc.exists) {
                          final bookingData = bookingDoc.data();
                          if (deviceType == 'PS4' || deviceType == 'PS5') {
                            slotCount = (bookingData?['consoleCount'] as num?)?.toInt() ?? 1;
                          } else if (deviceType == 'Theatre') {
                            slotCount = (bookingData?['totalPeople'] as num?)?.toInt() ?? 1;
                          } else if (deviceType == 'VR' || deviceType == 'Simulator') {
                            slotCount = 1; // VR/Simulator always count as 1 slot
                          }
                        }
                      } catch (e) {
                        debugPrint('Error getting slot count from booking: $e');
                      }
                    }
                    occupiedCount += slotCount;
                  }
                }
              }
            } catch (e) {
              debugPrint('Error processing booking time slot: $e');
            }
          }

          // Also check actual service start time (for sessions not from bookings)
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
                occupiedCount++;
              }
            } catch (e) {
              debugPrint('Error parsing session time: $e');
              continue;
            }
          }
        }

        // Also check closed sessions for today's date
        // IMPORTANT: For closed sessions, use actual endTime if available
        // This ensures slots are freed up when sessions end early
        if (date == todayId) {
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
              
              // Get actual session end time if available
              final sessionEndTime = sessionData['endTime'] as Timestamp?;
              DateTime? actualEndTime;
              if (sessionEndTime != null) {
                actualEndTime = sessionEndTime.toDate();
              }

              for (var service in services) {
                final serviceType = service['type'] as String? ?? '';
                if (serviceType != deviceType) continue;

                final startTimeStr = service['startTime'] as String? ?? '';
                if (startTimeStr.isEmpty) continue;

                try {
                  final startTime = DateTime.parse(startTimeStr);
                  final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);
                  if (serviceDateId != date) continue;

                  // Use actual end time if session ended early, otherwise use scheduled duration
                  double serviceEndDecimal;
                  if (actualEndTime != null && actualEndTime.isBefore(startTime.add(Duration(hours: 24)))) {
                    // Session ended early - use actual end time directly
                    serviceEndDecimal = actualEndTime.hour + (actualEndTime.minute / 60.0);
                    // If end time is on a different day, use the scheduled end time instead
                    final endDateId = DateFormat('yyyy-MM-dd').format(actualEndTime);
                    if (endDateId != date) {
                      // End time is on different date, use scheduled duration
                      final hours = (service['hours'] as num?)?.toInt() ?? 0;
                      final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                      final serviceDurationHours = hours + (minutes / 60.0);
                      final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
                      serviceEndDecimal = serviceStartDecimal + serviceDurationHours;
                    }
                  } else {
                    // Use scheduled duration (session completed full duration or no end time recorded)
                    final hours = (service['hours'] as num?)?.toInt() ?? 0;
                    final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                    final serviceDurationHours = hours + (minutes / 60.0);
                    final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
                    serviceEndDecimal = serviceStartDecimal + serviceDurationHours;
                  }

                  final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);

                  // Check for overlap
                  if ((startDecimal < serviceEndDecimal && endDecimal > serviceStartDecimal)) {
                    occupiedCount++;
                  }
                } catch (e) {
                  debugPrint('Error parsing closed session time: $e');
                  continue;
                }
              }
            }
          } catch (e) {
            debugPrint('Error checking closed sessions: $e');
          }
        }
      } else {
        // For past dates, check history sessions
        // Use actual endTime if available for past sessions too
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
            
            // Get actual session end time if available
            final sessionEndTime = sessionData['endTime'] as Timestamp?;
            DateTime? actualEndTime;
            if (sessionEndTime != null) {
              actualEndTime = sessionEndTime.toDate();
            }

            for (var service in services) {
              final serviceType = service['type'] as String? ?? '';
              if (serviceType != deviceType) continue;

              final startTimeStr = service['startTime'] as String? ?? '';
              if (startTimeStr.isEmpty) continue;

              try {
                final startTime = DateTime.parse(startTimeStr);
                final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);
                if (serviceDateId != date) continue;

                // Use actual end time if session ended early, otherwise use scheduled duration
                double serviceEndDecimal;
                if (actualEndTime != null) {
                  final endDateId = DateFormat('yyyy-MM-dd').format(actualEndTime);
                  if (endDateId == date) {
                    // End time is on same date - use actual end time directly
                    serviceEndDecimal = actualEndTime.hour + (actualEndTime.minute / 60.0);
                  } else {
                    // End time is on different date, use scheduled duration
                    final hours = (service['hours'] as num?)?.toInt() ?? 0;
                    final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                    final serviceDurationHours = hours + (minutes / 60.0);
                    final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
                    serviceEndDecimal = serviceStartDecimal + serviceDurationHours;
                  }
                } else {
                  // Use scheduled duration (no end time recorded)
                  final hours = (service['hours'] as num?)?.toInt() ?? 0;
                  final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                  final serviceDurationHours = hours + (minutes / 60.0);
                  final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
                  serviceEndDecimal = serviceStartDecimal + serviceDurationHours;
                }

                final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);

                // Check for overlap
                if ((startDecimal < serviceEndDecimal && endDecimal > serviceStartDecimal)) {
                  occupiedCount++;
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

      return occupiedCount;
    } catch (e) {
      debugPrint('Error counting occupied slots: $e');
      return 0;
    }
  }

  /// Check if a booking can be made (has available slots)
  /// Returns true if booking is allowed, false if capacity is full
  static Future<bool> canMakeBooking({
    required String deviceType,
    required String date,
    required String timeSlot,
    required double durationHours,
  }) async {
    try {
      final capacity = await getDeviceCapacity(deviceType);
      if (capacity == 0) {
        // If capacity is 0, allow booking (backward compatibility)
        // Admin should set capacity > 0 to enable slot management
        return true;
      }

      final occupiedSlots = await countOccupiedSlots(
        deviceType: deviceType,
        date: date,
        timeSlot: timeSlot,
        durationHours: durationHours,
      );

      return occupiedSlots < capacity;
    } catch (e) {
      debugPrint('Error checking booking capacity: $e');
      return false; // On error, block booking for safety
    }
  }

  /// Get available slots count for a given date, time, and device type
  /// Returns -1 if capacity is 0 (unlimited), otherwise returns available slots count
  /// Uses caching to avoid repeated queries
  static Future<int> getAvailableSlots({
    required String deviceType,
    required String date,
    required String timeSlot,
    required double durationHours,
  }) async {
    try {
      // Create cache key
      final cacheKey = '$deviceType|$date|$timeSlot|$durationHours';
      
      // Check cache first (only if cache is recent)
      if (_cachedAvailableSlots != null &&
          _slotsCacheTime != null &&
          DateTime.now().difference(_slotsCacheTime!) < _slotsCacheDuration) {
        if (_cachedAvailableSlots!.containsKey(cacheKey)) {
          return _cachedAvailableSlots![cacheKey]!;
        }
      } else {
        // Clear old cache if expired
        _cachedAvailableSlots = {};
        _slotsCacheTime = DateTime.now();
      }
      
      final capacity = await getDeviceCapacity(deviceType);
      if (capacity == 0) {
        // If capacity is 0, return -1 to indicate unlimited (not 999 to avoid confusion)
        _cachedAvailableSlots![cacheKey] = -1;
        return -1;
      }

      final occupiedSlots = await countOccupiedSlots(
        deviceType: deviceType,
        date: date,
        timeSlot: timeSlot,
        durationHours: durationHours,
      );

      final availableSlots = (capacity - occupiedSlots).clamp(0, capacity);
      
      // Cache the result
      _cachedAvailableSlots![cacheKey] = availableSlots;
      
      return availableSlots;
    } catch (e) {
      debugPrint('Error getting available slots: $e');
      return 0;
    }
  }

  /// Generate next available slot ID for a device type
  /// Format: PS5-1, PS5-2, etc.
  static Future<String> getNextSlotId(String deviceType) async {
    try {
      // Get all bookings with slot IDs for this device type
      final bookingsSnapshot = await _firestore
          .collection('bookings')
          .where('serviceType', isEqualTo: deviceType)
          .get();

      final Set<int> usedSlotNumbers = {};
      
      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final slotId = data['slotId'] as String?;
        if (slotId != null && slotId.startsWith('$deviceType-')) {
          final slotNumberStr = slotId.replaceFirst('$deviceType-', '');
          final slotNumber = int.tryParse(slotNumberStr);
          if (slotNumber != null) {
            usedSlotNumbers.add(slotNumber);
          }
        }
      }

      // Find next available slot number
      final capacity = await getDeviceCapacity(deviceType);
      if (capacity > 0) {
        for (int i = 1; i <= capacity; i++) {
          if (!usedSlotNumbers.contains(i)) {
            return '$deviceType-$i';
          }
        }
        // If all slots are used, return the next number beyond capacity
        // (This shouldn't happen if capacity checks work correctly)
        return '$deviceType-${capacity + 1}';
      } else {
        // If capacity is 0, just use sequential numbering
        final nextNumber = usedSlotNumbers.isEmpty 
            ? 1 
            : (usedSlotNumbers.reduce((a, b) => a > b ? a : b) + 1);
        return '$deviceType-$nextNumber';
      }
    } catch (e) {
      debugPrint('Error generating slot ID: $e');
      // Fallback: return timestamp-based ID
      return '$deviceType-${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}

