import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/booking_logic_service.dart';
import '../services/device_capacity_service.dart';
import '../services/session_service.dart';

class CreateBookingPage extends StatefulWidget {
  final DateTime selectedDate;
  final String? serviceType;

  const CreateBookingPage({super.key, required this.selectedDate, this.serviceType});

  @override
  State<CreateBookingPage> createState() => _CreateBookingPageState();
}

class _CreateBookingPageState extends State<CreateBookingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String? _selectedServiceType;
  String? _selectedTimeSlot;
  bool _useCustomTime = false;
  TimeOfDay? _customTime;

  // Selected date for booking
  late DateTime _selectedDate;

  // PS4/PS5 fields
  int _consoleCount = 1;
  int _durationHours = 1;
  int _minutes = 0;
  int _additionalControllers = 0;

  // Theatre fields
  int _theatreHours = 1;
  int _theatrePeople = 1;

  // VR/Simulator fields - based on people (1 game per person)
  int _numberOfPeople = 1;

  // Price calculation
  double _calculatedPrice = 0.0;
  bool _priceCalculated = false;

  // Booked time slots for the selected date and service type
  Set<String> _bookedTimeSlots = {};

  // Device capacity info
  int _deviceCapacity = 0;
  bool _loadingCapacity = false;

  // Pre-loaded available slots for each time slot (to avoid FutureBuilder spinners)
  Map<String, int> _availableSlotsCache = {};
  bool _loadingSlots = false;

  // User history search
  final SessionService _sessionService = SessionService();
  Map<String, dynamic>? _foundUserHistory;
  bool _searchCompleted = false;
  int _phoneLength = 0;

  // Common scenarios
  List<Map<String, dynamic>> _commonScenarios = [];
  bool _loadingScenarios = true;
  String? _scenariosError;

  final List<String> _serviceTypes = ['PS5', 'PS4', 'VR', 'Simulator', 'Theatre'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _selectedServiceType = widget.serviceType ?? 'PS5';
    _calculatePrice();
    _loadBookedTimeSlots();
    _loadCommonScenarios();
    _loadDeviceCapacity();
  }

  Future<void> _loadDeviceCapacity() async {
    if (_selectedServiceType == null) return;

    setState(() {
      _loadingCapacity = true;
    });

    try {
      final capacity = await DeviceCapacityService.getDeviceCapacity(_selectedServiceType!);
      setState(() {
        _deviceCapacity = capacity;
        _loadingCapacity = false;
      });

      // Preload slots after capacity is loaded
      if (capacity > 0) {
        _preloadAvailableSlots();
      }
    } catch (e) {
      debugPrint('Error loading device capacity: $e');
      setState(() {
        _loadingCapacity = false;
      });
    }
  }

  // Load common scenarios using Future instead of Stream
  Future<void> _loadCommonScenarios() async {
    setState(() {
      _loadingScenarios = true;
      _scenariosError = null;
    });

    try {
      debugPrint('Loading common scenarios from Firestore...');

      // Try with orderBy first
      QuerySnapshot snapshot;
      try {
        snapshot =
            await _firestore
                .collection('common_scenarios')
                .orderBy('order', descending: false)
                .get();
        debugPrint('Common scenarios loaded with orderBy: ${snapshot.docs.length} docs');
      } catch (e) {
        // If orderBy fails, try without it
        debugPrint('OrderBy failed, trying without order: $e');
        snapshot = await _firestore.collection('common_scenarios').get();
        debugPrint('Common scenarios loaded without orderBy: ${snapshot.docs.length} docs');
      }

      if (snapshot.docs.isEmpty) {
        debugPrint('No common scenarios found in Firestore');
        setState(() {
          _commonScenarios = [];
          _loadingScenarios = false;
        });
        return;
      }

      // Parse and sort scenarios
      final List<Map<String, dynamic>> scenarios = [];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          scenarios.add({
            'id': doc.id,
            'type': data['type'] ?? 'PS5',
            'count': (data['count'] as num?)?.toInt() ?? 1,
            'hours': (data['hours'] as num?)?.toInt() ?? 1,
            'minutes': (data['minutes'] as num?)?.toInt() ?? 0,
            'additionalControllers': (data['additionalControllers'] as num?)?.toInt() ?? 0,
            'label': data['label'] ?? '',
            'order': (data['order'] as num?)?.toInt() ?? 0,
          });
        } catch (e) {
          debugPrint('Error parsing scenario ${doc.id}: $e');
        }
      }

      // Sort by order
      scenarios.sort((a, b) {
        final orderA = a['order'] as int? ?? 0;
        final orderB = b['order'] as int? ?? 0;
        return orderA.compareTo(orderB);
      });

      debugPrint('Parsed ${scenarios.length} common scenarios');

      setState(() {
        _commonScenarios = scenarios;
        _loadingScenarios = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading common scenarios: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _scenariosError = e.toString();
        _loadingScenarios = false;
        _commonScenarios = [];
      });
    }
  }

  // Load booked time slots for the selected date and service
  Future<void> _loadBookedTimeSlots() async {
    if (_selectedServiceType == null) return;

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Get all bookings for this date and service type
      final bookingsSnapshot =
          await _firestore
              .collection('bookings')
              .where('date', isEqualTo: dateId)
              .where('serviceType', isEqualTo: _selectedServiceType)
              .get();

      final Set<String> bookedSlots = {};

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final timeSlot = data['timeSlot'] as String? ?? '';
        final durationHours = (data['durationHours'] as num?)?.toDouble() ?? 1.0;
        final status = (data['status'] as String? ?? 'pending').toLowerCase().trim();

        // Skip cancelled bookings
        if (status == 'cancelled') continue;
        if (timeSlot.isEmpty) continue;

        // Parse time slot and calculate all affected slots
        final parts = timeSlot.split(':');
        if (parts.length == 2) {
          final startHour = int.tryParse(parts[0]) ?? 0;
          final startMinute = int.tryParse(parts[1]) ?? 0;
          final startDecimal = startHour + (startMinute / 60.0);
          final endDecimal = startDecimal + durationHours;

          // Mark all affected time slots
          for (double hour = startDecimal; hour < endDecimal; hour += 0.5) {
            final slotHour = hour.floor();
            final slotMinute = ((hour - slotHour) * 60).round();
            final slotStr =
                '${slotHour.toString().padLeft(2, '0')}:${slotMinute.toString().padLeft(2, '0')}';
            bookedSlots.add(slotStr);
          }
        }
      }

      // Check if date is in the past
      final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isPastDate = dateId.compareTo(todayId) < 0;

      // Check active sessions (for today/future dates)
      if (!isPastDate) {
        final activeSessionsSnapshot =
            await _firestore
                .collection('active_sessions')
                .where('status', isEqualTo: 'active')
                .get();

        for (var sessionDoc in activeSessionsSnapshot.docs) {
          final sessionData = sessionDoc.data();
          final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

          for (var service in services) {
            final serviceType = service['type'] as String? ?? '';
            if (serviceType != _selectedServiceType) continue;

            final startTimeStr = service['startTime'] as String? ?? '';
            if (startTimeStr.isEmpty) continue;

            try {
              final startTime = DateTime.parse(startTimeStr);
              final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);

              // Only check for the same date
              if (serviceDateId != dateId) continue;

              final hours = (service['hours'] as num?)?.toInt() ?? 0;
              final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
              final durationHours = hours + (minutes / 60.0);

              final startDecimal = startTime.hour + (startTime.minute / 60.0);
              final endDecimal = startDecimal + durationHours;

              // Mark all affected time slots
              for (double hour = startDecimal; hour < endDecimal; hour += 0.5) {
                final slotHour = hour.floor();
                final slotMinute = ((hour - slotHour) * 60).round();
                final slotStr =
                    '${slotHour.toString().padLeft(2, '0')}:${slotMinute.toString().padLeft(2, '0')}';
                bookedSlots.add(slotStr);
              }
            } catch (e) {
              debugPrint('Error parsing session start time: $e');
            }
          }
        }

        // Also check closed sessions for today's date
        // This ensures completed sessions today remain marked as unavailable
        try {
          if (dateId == todayId) {
            final historySessionsSnapshot =
                await _firestore
                    .collection('days')
                    .doc(dateId)
                    .collection('sessions')
                    .where('status', isEqualTo: 'closed')
                    .get();

            for (var sessionDoc in historySessionsSnapshot.docs) {
              final sessionData = sessionDoc.data();
              final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

              for (var service in services) {
                final serviceType = service['type'] as String? ?? '';
                if (serviceType != _selectedServiceType) continue;

                final startTimeStr = service['startTime'] as String? ?? '';
                if (startTimeStr.isEmpty) continue;

                try {
                  final startTime = DateTime.parse(startTimeStr);
                  final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);

                  // Only check for the same date
                  if (serviceDateId != dateId) continue;

                  final hours = (service['hours'] as num?)?.toInt() ?? 0;
                  final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                  final durationHours = hours + (minutes / 60.0);

                  final startDecimal = startTime.hour + (startTime.minute / 60.0);
                  final endDecimal = startDecimal + durationHours;

                  // Mark all affected time slots
                  for (double hour = startDecimal; hour < endDecimal; hour += 0.5) {
                    final slotHour = hour.floor();
                    final slotMinute = ((hour - slotHour) * 60).round();
                    final slotStr =
                        '${slotHour.toString().padLeft(2, '0')}:${slotMinute.toString().padLeft(2, '0')}';
                    bookedSlots.add(slotStr);
                  }
                } catch (e) {
                  debugPrint('Error parsing closed session start time: $e');
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
          final historySessionsSnapshot =
              await _firestore
                  .collection('days')
                  .doc(dateId)
                  .collection('sessions')
                  .where('status', isEqualTo: 'closed')
                  .get();

          for (var sessionDoc in historySessionsSnapshot.docs) {
            final sessionData = sessionDoc.data();
            final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

            for (var service in services) {
              final serviceType = service['type'] as String? ?? '';
              if (serviceType != _selectedServiceType) continue;

              final startTimeStr = service['startTime'] as String? ?? '';
              if (startTimeStr.isEmpty) continue;

              try {
                final startTime = DateTime.parse(startTimeStr);
                final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);

                // Only check for the same date
                if (serviceDateId != dateId) continue;

                final hours = (service['hours'] as num?)?.toInt() ?? 0;
                final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                final durationHours = hours + (minutes / 60.0);

                final startDecimal = startTime.hour + (startTime.minute / 60.0);
                final endDecimal = startDecimal + durationHours;

                // Mark all affected time slots
                for (double hour = startDecimal; hour < endDecimal; hour += 0.5) {
                  final slotHour = hour.floor();
                  final slotMinute = ((hour - slotHour) * 60).round();
                  final slotStr =
                      '${slotHour.toString().padLeft(2, '0')}:${slotMinute.toString().padLeft(2, '0')}';
                  bookedSlots.add(slotStr);
                }
              } catch (e) {
                debugPrint('Error parsing history session start time: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('Error checking history sessions: $e');
        }
      }

      setState(() {
        _bookedTimeSlots = bookedSlots;
      });
    } catch (e) {
      debugPrint('Error loading booked time slots: $e');
    }
  }

  Future<void> _calculatePrice() async {
    if (_selectedServiceType == null) {
      setState(() {
        _calculatedPrice = 0.0;
        _priceCalculated = false;
      });
      return;
    }

    double price = 0.0;

    if (_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4') {
      // Calculate price for one console first
      final singleConsolePrice = await BookingLogicService.calculateBookingPrice(
        deviceType: _selectedServiceType!,
        hours: _durationHours,
        minutes: _minutes,
        additionalControllers: _additionalControllers,
      );
      // Multiply by console count
      price = singleConsolePrice * _consoleCount;
    } else if (_selectedServiceType == 'VR' || _selectedServiceType == 'Simulator') {
      // VR/Simulator: 1 game per person
      // Price = price per person × number of people
      // Get price per person from admin settings
      final pricePerPerson = await BookingLogicService.getPricePerPerson(
        deviceType: _selectedServiceType!,
      );
      price = pricePerPerson * _numberOfPeople;
    } else if (_selectedServiceType == 'Theatre') {
      price = await BookingLogicService.calculateBookingPrice(
        deviceType: _selectedServiceType!,
        hours: _theatreHours,
        minutes: 0,
        additionalControllers: 0,
        people: _theatrePeople,
      );
    }

    setState(() {
      _calculatedPrice = price;
      _priceCalculated = true;
    });
  }

  void _onServiceTypeChanged(String? type) {
    setState(() {
      _selectedServiceType = type;
      _selectedTimeSlot = null;
      _useCustomTime = false;
      _customTime = null;
      // Reset price calculation flag to force recalculation
      _priceCalculated = false;
      _calculatedPrice = 0.0;
    });
    // Recalculate price with new service type
    _calculatePrice();
    _loadBookedTimeSlots();
    _loadDeviceCapacity();
    _preloadAvailableSlots(); // Preload slots for new service type
  }

  /// Search for user history by phone number
  Future<void> _searchUserHistory() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.length != 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid 10-digit mobile number'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Prevent duplicate searches for the same number
    if (_foundUserHistory != null) {
      final historyPhone = _foundUserHistory!['phoneNumber'] as String?;
      if (historyPhone != null) {
        final cleanHistoryPhone = historyPhone.replaceAll(RegExp(r'[^\d]'), '');
        final cleanInputPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
        if (cleanHistoryPhone == cleanInputPhone) {
          return; // Already searched this exact number
        }
      }
    }

    // Update UI to show searching state
    if (mounted) {
      setState(() {
        _foundUserHistory = null; // Clear previous result
        _searchCompleted = false; // Mark as searching
      });
    }

    // Show loading indicator
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16),
              Text('Searching user history...'),
            ],
          ),
          duration: Duration(seconds: 10),
        ),
      );
    }

    try {
      // Add timeout to prevent hanging
      final historyData = await _sessionService
          .searchUserHistoryByPhone(phoneNumber)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint('Search timeout for phone: $phoneNumber');
              return null;
            },
          );

      if (!mounted) return;

      // Update state immediately
      setState(() {
        _foundUserHistory = historyData;
        _searchCompleted = true; // Mark search as completed
        if (historyData != null && _nameController.text.trim().isEmpty) {
          // Auto-fill name if field is empty
          final customerName = historyData['customerName'] as String? ?? '';
          // Extract name if it contains phone number in format "Name (phone)"
          if (customerName.contains('(')) {
            _nameController.text = customerName.split('(')[0].trim();
          } else {
            _nameController.text = customerName;
          }
        }
      });

      // Show result message only if user found
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (historyData != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ User found in history!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      // No snackbar for "not found" - it's shown in helper text in red
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error searching history: ${e.toString().length > 50 ? e.toString().substring(0, 50) + "..." : e.toString()}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _foundUserHistory = null;
        _searchCompleted = true; // Mark as completed even on error
      });
    }
  }

  /// Get max available slots for the selected time slot
  Future<int> _getMaxAvailableForSelectedTime() async {
    if (_selectedServiceType == null || _deviceCapacity == 0) {
      return _deviceCapacity > 0 ? _deviceCapacity : -1;
    }

    if (_selectedTimeSlot == null && !_useCustomTime) {
      return _deviceCapacity > 0 ? _deviceCapacity : -1;
    }

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
      String timeSlot24Hour;

      if (_useCustomTime && _customTime != null) {
        timeSlot24Hour =
            '${_customTime!.hour.toString().padLeft(2, '0')}:${_customTime!.minute.toString().padLeft(2, '0')}';
      } else if (_selectedTimeSlot != null) {
        timeSlot24Hour = _formatTime24Hour(_selectedTimeSlot!);
      } else {
        return _deviceCapacity > 0 ? _deviceCapacity : -1;
      }

      double durationHours = 1.0;
      if (_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') {
        durationHours = _durationHours + (_minutes / 60.0);
      } else if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR') {
        // For VR/Simulator, duration is based on number of people (games)
        // But for slot availability check, we use a minimum duration (e.g., 30 minutes)
        // since multiple people can use the same slot
        durationHours = (_numberOfPeople * 5) / 60.0;
        // Ensure minimum duration of 30 minutes for slot checking
        if (durationHours < 0.5) durationHours = 0.5;
      } else if (_selectedServiceType == 'Theatre') {
        durationHours = _theatreHours.toDouble();
      }

      return await DeviceCapacityService.getAvailableSlots(
        deviceType: _selectedServiceType!,
        date: dateId,
        timeSlot: timeSlot24Hour,
        durationHours: durationHours,
      );
    } catch (e) {
      debugPrint('Error getting max available: $e');
      return _deviceCapacity > 0 ? _deviceCapacity : -1;
    }
  }

  /// Preload available slots for all time slots to avoid FutureBuilder spinners
  Future<void> _preloadAvailableSlots() async {
    if (_selectedServiceType == null || _deviceCapacity == 0) {
      return; // No need to preload if capacity is 0 (unlimited)
    }

    setState(() {
      _loadingSlots = true;
    });

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final timeSlots24Hour = [
        '09:00',
        '09:30',
        '10:00',
        '10:30',
        '11:00',
        '11:30',
        '12:00',
        '12:30',
        '13:00',
        '13:30',
        '14:00',
        '14:30',
        '15:00',
        '15:30',
        '16:00',
        '16:30',
        '17:00',
        '17:30',
        '18:00',
        '18:30',
        '19:00',
        '19:30',
        '20:00',
        '20:30',
        '21:00',
        '21:30',
        '22:00',
        '22:30',
        '23:00',
        '23:30',
      ];

      const slotCheckDurationHours = 0.5; // 30 minutes per slot

      // Load all slots in parallel
      final futures = timeSlots24Hour.map((slot) async {
        final availableSlots = await DeviceCapacityService.getAvailableSlots(
          deviceType: _selectedServiceType!,
          date: dateId,
          timeSlot: slot,
          durationHours: slotCheckDurationHours,
        );
        return MapEntry(slot, availableSlots);
      });

      final results = await Future.wait(futures);
      final newCache = <String, int>{};
      for (var entry in results) {
        newCache[entry.key] = entry.value;
      }

      if (mounted) {
        setState(() {
          _availableSlotsCache = newCache;
          _loadingSlots = false;
        });
      }
    } catch (e) {
      debugPrint('Error preloading available slots: $e');
      if (mounted) {
        setState(() {
          _loadingSlots = false;
        });
      }
    }
  }

  Future<void> _createBooking() async {
    // Validate customer information
    final customerName = _nameController.text.trim();
    final phoneNumber = _phoneController.text.trim();

    if (customerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name'), backgroundColor: Colors.red),
      );
      return;
    }

    if (customerName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer name must be at least 2 characters'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (phoneNumber.isNotEmpty) {
      // Phone validation - must be exactly 10 digits
      final phoneDigits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (phoneDigits.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid 10-digit mobile number'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validate time slot
    if (_selectedTimeSlot == null && !_useCustomTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_useCustomTime && _customTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a custom time'), backgroundColor: Colors.red),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
      String timeSlot24Hour;
      if (_useCustomTime && _customTime != null) {
        // Custom time is already in 24-hour format
        timeSlot24Hour =
            '${_customTime!.hour.toString().padLeft(2, '0')}:${_customTime!.minute.toString().padLeft(2, '0')}';
      } else {
        // Convert selected time slot from 12-hour to 24-hour format
        timeSlot24Hour = _formatTime24Hour(_selectedTimeSlot!);
      }

      // Calculate duration
      double durationHours = 1.0;
      if (_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') {
        durationHours = _durationHours + (_minutes / 60.0);
      } else if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR') {
        // 1 game per person, 5 minutes per game
        final totalGames = _numberOfPeople;
        durationHours = (totalGames * 5) / 60.0;
      } else if (_selectedServiceType == 'Theatre') {
        durationHours = _theatreHours.toDouble();
      }

      // Check for conflicts and capacity
      // First check if we have enough slots for the requested count
      if (_deviceCapacity > 0) {
        final availableSlots = await DeviceCapacityService.getAvailableSlots(
          deviceType: _selectedServiceType!,
          date: dateId,
          timeSlot: timeSlot24Hour,
          durationHours: durationHours,
        );

        // Determine required count based on service type
        int requiredCount = 1;
        if (_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4') {
          requiredCount = _consoleCount;
        } else if (_selectedServiceType == 'VR' || _selectedServiceType == 'Simulator') {
          // For VR/Simulator, only need 1 slot (multiple people can use same slot)
          requiredCount = 1;
        } else if (_selectedServiceType == 'Theatre') {
          requiredCount = _theatrePeople;
        }

        if (availableSlots < requiredCount) {
          if (mounted) {
            Navigator.pop(context); // Close loading

            final capacity = await DeviceCapacityService.getDeviceCapacity(_selectedServiceType!);
            String errorMessage;
            if (availableSlots == 0) {
              errorMessage =
                  'All $capacity ${_selectedServiceType} slots are booked for this time. Please choose a different time.';
            } else {
              final countLabel =
                  _selectedServiceType == 'PS5' || _selectedServiceType == 'PS4'
                      ? 'console${requiredCount > 1 ? 's' : ''}'
                      : 'slot${requiredCount > 1 ? 's' : ''}';
              errorMessage =
                  'Only $availableSlots ${_selectedServiceType} slot${availableSlots > 1 ? 's' : ''} available, but you need $requiredCount $countLabel. Please reduce the count or choose a different time.';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Check for conflicts (for other service types or when capacity is 0)
      final hasConflict = await BookingLogicService.hasTimeConflict(
        deviceType: _selectedServiceType!,
        date: dateId,
        timeSlot: timeSlot24Hour,
        durationHours: durationHours,
      );

      if (hasConflict) {
        if (mounted) {
          Navigator.pop(context); // Close loading

          // Get capacity info for better error message
          final capacity = await DeviceCapacityService.getDeviceCapacity(_selectedServiceType!);
          final availableSlots = await DeviceCapacityService.getAvailableSlots(
            deviceType: _selectedServiceType!,
            date: dateId,
            timeSlot: timeSlot24Hour,
            durationHours: durationHours,
          );

          String errorMessage;
          if (capacity > 0 && availableSlots == 0) {
            errorMessage =
                'All ${capacity} ${_selectedServiceType} slots are booked for this time. Please choose a different time.';
          } else {
            errorMessage = 'This time slot conflicts with an existing booking or active session.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Get next available slot ID
      final slotId = await DeviceCapacityService.getNextSlotId(_selectedServiceType!);

      // Create booking data
      final bookingData = {
        'customerName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'date': dateId,
        'timeSlot': timeSlot24Hour,
        'serviceType': _selectedServiceType,
        'durationHours': durationHours,
        'slotId': slotId, // Assign slot ID
        if (_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4') ...{
          'consoleCount': _consoleCount,
          'additionalControllers': _additionalControllers,
        },
        if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR') ...{
          'numberOfPeople': _numberOfPeople,
          'numberOfGames': _numberOfPeople, // 1 game per person
          'durationMinutes': _numberOfPeople * 5, // 5 minutes per game
        },
        if (_selectedServiceType == 'Theatre') ...{
          'hours': _theatreHours,
          'totalPeople': _theatrePeople,
        },
        'status': 'pending',
      };

      await _firestore.collection('bookings').add(bookingData);

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pop(context); // Go back to bookings page

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating booking: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyQuickAddScenario({
    required String type,
    required int count,
    required int hours,
    required int minutes,
    required int additionalControllers,
  }) {
    setState(() {
      _selectedServiceType = type;
      _selectedTimeSlot = null; // Reset time slot when applying scenario

      if (type == 'PS5' || type == 'PS4') {
        _consoleCount = count;
        _durationHours = hours;
        _minutes = minutes;
        _additionalControllers = additionalControllers;
      } else if (type == 'VR' || type == 'Simulator') {
        // Use count as number of people (each person gets 1 game)
        _numberOfPeople = count.clamp(1, double.infinity).toInt();
      } else if (type == 'Theatre') {
        _theatreHours = hours;
        _theatrePeople = count; // Use count as number of people for Theatre
      }

      // Reset price calculation flag to force recalculation
      _priceCalculated = false;
      _calculatedPrice = 0.0;
    });
    _calculatePrice();
    _loadBookedTimeSlots(); // Reload booked slots for the new service type
    _loadDeviceCapacity(); // Reload capacity for new service type
  }

  Widget _buildQuickAddSection() {
    // Show loading state
    if (_loadingScenarios) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200, width: 1),
        ),
        child: const Center(
          child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    // Show error state
    if (_scenariosError != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Error loading Quick Access scenarios',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, size: 18, color: Colors.red.shade700),
                  onPressed: _loadCommonScenarios,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _scenariosError!,
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    // Show empty state
    if (_commonScenarios.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.flash_on, size: 18, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Quick Access - No scenarios configured',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh, size: 18, color: Colors.blue.shade700),
              onPressed: _loadCommonScenarios,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }

    // Show scenarios
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on, size: 18, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Quick Access (${_commonScenarios.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 16, color: Colors.blue.shade700),
                onPressed: _loadCommonScenarios,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 50, // Fixed height for scrollable row
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _commonScenarios.map((scenario) {
                      final type = scenario['type'] as String? ?? 'PS5';
                      final count = (scenario['count'] as num?)?.toInt() ?? 1;
                      final hours = (scenario['hours'] as num?)?.toInt() ?? 1;
                      final minutes = (scenario['minutes'] as num?)?.toInt() ?? 0;
                      final additionalControllers =
                          (scenario['additionalControllers'] as num?)?.toInt() ?? 0;
                      final label =
                          scenario['label'] as String? ??
                          '$count $type${hours > 0 ? ' ${hours}h' : ''}${additionalControllers > 0 ? ' Multi' : ''}';
                      final color =
                          type == 'PS5'
                              ? Colors.blue
                              : type == 'PS4'
                              ? Colors.purple
                              : type == 'VR'
                              ? Colors.green
                              : type == 'Simulator'
                              ? Colors.orange
                              : Colors.teal;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap:
                              () => _applyQuickAddScenario(
                                type: type,
                                count: count,
                                hours: hours,
                                minutes: minutes,
                                additionalControllers: additionalControllers,
                              ),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  additionalControllers > 0 ? Icons.people : Icons.sports_esports,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Booking')),
      body: Column(
        children: [
          // Quick Access: Common Scenarios (Quick Add)
          _buildQuickAddSection(),

          const Divider(),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Selection
                  _buildDateSection(),

                  const SizedBox(height: 24),

                  // Customer Information
                  _buildCustomerInfoSection(),

                  const SizedBox(height: 24),

                  // Service Type Selection
                  _buildServiceTypeSection(),

                  const SizedBox(height: 24),

                  _buildTimeSlotSection(),

                  const SizedBox(height: 24),

                  // Device Capacity Info
                  if (_selectedServiceType != null && !_loadingCapacity)
                    _buildCapacityInfoSection(),

                  const SizedBox(height: 24),

                  // Service-specific configuration
                  _buildServiceConfigSection(),

                  const SizedBox(height: 24),

                  // Time Slot Selection

                  // Price Display
                  if (_priceCalculated) _buildPriceSection(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Create Button at Bottom
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.grey.shade300, blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _createBooking,
                  icon: const Icon(Icons.add_circle, size: 24),
                  label: const Text(
                    'Create Booking',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Booking Date', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final maxDate = now.add(const Duration(days: 30));

            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: now,
              lastDate: maxDate,
              selectableDayPredicate: (date) {
                return date.isAfter(now.subtract(const Duration(days: 1))) &&
                    date.isBefore(maxDate.add(const Duration(days: 1)));
              },
            );

            if (picked != null && picked != _selectedDate) {
              setState(() {
                _selectedDate = picked;
                _selectedTimeSlot = null; // Clear time slot when date changes
              });
              _loadBookedTimeSlots(); // Reload booked slots for new date
              _preloadAvailableSlots(); // Reload available slots for new date
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade300, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.purple.shade700, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected Date',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.purple.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.purple.shade700, size: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Information',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Customer Name *',
            hintText: 'Enter customer name (required, min 2 characters)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          decoration: InputDecoration(
            labelText: 'Phone Number',
            hintText: 'Enter 10-digit mobile number (optional)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.phone),
            suffixIcon:
                _phoneLength == 10
                    ? IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchUserHistory(),
                      tooltip: 'Search user history',
                    )
                    : null,
            counterText: '',
            helperText:
                _foundUserHistory != null
                    ? '✓ User found in history!'
                    : (_searchCompleted && _foundUserHistory == null)
                    ? 'No user found'
                    : _phoneLength == 10
                    ? 'Tap search icon or wait...'
                    : 'Enter 10 digit mobile number',
            helperMaxLines: 2,
            helperStyle: TextStyle(
              color:
                  (_searchCompleted && _foundUserHistory == null)
                      ? Colors.red
                      : _foundUserHistory != null
                      ? Colors.green
                      : null,
            ),
          ),
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          onChanged: (value) {
            setState(() {
              _phoneLength = value.length;

              // Clear found history and search status when number changes
              if (_foundUserHistory != null || _searchCompleted) {
                _foundUserHistory = null;
                _searchCompleted = false;
              }
            });

            // Auto-search when 10 digits are entered
            if (value.length == 10) {
              // Small delay to ensure UI updates first
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && _phoneController.text.length == 10) {
                  _searchUserHistory();
                }
              });
            }
          },
        ),
        if (_foundUserHistory != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'User found: ${_foundUserHistory!['customerName'] ?? 'Unknown'}',
                    style: TextStyle(fontWeight: FontWeight.w500, color: Colors.green.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Service Type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              _serviceTypes.map((type) {
                final isSelected = _selectedServiceType == type;
                Color color;
                IconData icon;

                switch (type) {
                  case 'PS5':
                    color = Colors.blue;
                    icon = Icons.sports_esports;
                    break;
                  case 'PS4':
                    color = Colors.purple;
                    icon = Icons.videogame_asset;
                    break;
                  case 'VR':
                    color = Colors.purple.shade500;
                    icon = Icons.view_in_ar;
                    break;
                  case 'Simulator':
                    color = Colors.orange;
                    icon = Icons.directions_car;
                    break;
                  case 'Theatre':
                    color = Colors.red;
                    icon = Icons.movie;
                    break;
                  default:
                    color = Colors.grey;
                    icon = Icons.category;
                }

                return FilterChip(
                  selected: isSelected,
                  label: Text(type),
                  avatar: Icon(icon, size: 18),
                  onSelected: (selected) {
                    _onServiceTypeChanged(selected ? type : null);
                  },
                  selectedColor: color.withOpacity(0.3),
                  checkmarkColor: color,
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildServiceConfigSection() {
    if (_selectedServiceType == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_selectedServiceType} Configuration',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4') ...[
          // Console Count - restricted by available slots
          FutureBuilder<int>(
            future: _getMaxAvailableForSelectedTime(),
            builder: (context, snapshot) {
              final maxAvailable =
                  snapshot.hasData && snapshot.data! >= 0
                      ? snapshot.data!
                      : (_deviceCapacity > 0 ? _deviceCapacity : 999);

              // Ensure console count doesn't exceed available slots
              final maxConsoles = maxAvailable > 0 ? maxAvailable : 1;
              if (_consoleCount > maxConsoles && _deviceCapacity > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() {
                    _consoleCount = maxConsoles;
                  });
                });
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Number of Consoles:'),
                      if (_deviceCapacity > 0 && _selectedTimeSlot != null && snapshot.hasData)
                        Text(
                          snapshot.data! >= 0 ? 'Max available: $maxAvailable' : 'Unlimited',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          if (_consoleCount > 1) {
                            setState(() {
                              _consoleCount--;
                            });
                            _calculatePrice();
                          }
                        },
                      ),
                      Text(
                        '$_consoleCount',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              _consoleCount > maxConsoles && _deviceCapacity > 0
                                  ? Colors.red
                                  : null,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed:
                            _consoleCount < maxConsoles || _deviceCapacity == 0
                                ? () async {
                                  // Check available slots before allowing increase
                                  if (_deviceCapacity > 0 && _selectedTimeSlot != null) {
                                    final available = await _getMaxAvailableForSelectedTime();
                                    if (available < _consoleCount + 1) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Only $available slot${available > 1 ? 's' : ''} available at selected time. Cannot increase console count.',
                                          ),
                                          backgroundColor: Colors.orange,
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                      return;
                                    }
                                  }
                                  setState(() {
                                    _consoleCount++;
                                  });
                                  _calculatePrice();
                                }
                                : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Duration Hours
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Hours:'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      if (_durationHours > 1) {
                        setState(() {
                          _durationHours--;
                        });
                        _calculatePrice();
                      }
                    },
                  ),
                  Text(
                    '$_durationHours',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      setState(() {
                        _durationHours++;
                      });
                      _calculatePrice();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Minutes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Minutes:'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      if (_minutes > 0) {
                        setState(() {
                          _minutes -= 15;
                        });
                        _calculatePrice();
                      }
                    },
                  ),
                  Text(
                    '$_minutes',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      setState(() {
                        _minutes += 15;
                      });
                      _calculatePrice();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Additional Controllers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Additional Controllers:'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      if (_additionalControllers > 0) {
                        setState(() {
                          _additionalControllers--;
                        });
                        _calculatePrice();
                      }
                    },
                  ),
                  Text(
                    '$_additionalControllers',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      setState(() {
                        _additionalControllers++;
                      });
                      _calculatePrice();
                    },
                  ),
                ],
              ),
            ],
          ),
        ] else if (_selectedServiceType == 'VR' || _selectedServiceType == 'Simulator') ...[
          FutureBuilder<int>(
            future: _getMaxAvailableForSelectedTime(),
            builder: (context, snapshot) {
              final availableSlots =
                  snapshot.hasData && snapshot.data! >= 0
                      ? snapshot.data!
                      : (_deviceCapacity > 0 ? _deviceCapacity : -1);

              // For VR/Simulator, multiple people can use the same slot
              // Only check if at least 1 slot is available
              final hasAvailableSlot = availableSlots == -1 || availableSlots > 0;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Number of People:'),
                      if (_deviceCapacity > 0 && _selectedTimeSlot != null && snapshot.hasData)
                        Text(
                          availableSlots == -1
                              ? 'Unlimited slots'
                              : availableSlots > 0
                              ? '$availableSlots slot${availableSlots > 1 ? 's' : ''} available (multiple people per slot)'
                              : 'No slots available',
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                availableSlots > 0 || availableSlots == -1
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          if (_numberOfPeople > 1) {
                            setState(() {
                              _numberOfPeople--;
                            });
                            _calculatePrice();
                          }
                        },
                      ),
                      Text(
                        '$_numberOfPeople',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed:
                            hasAvailableSlot
                                ? () {
                                  setState(() {
                                    _numberOfPeople++;
                                  });
                                  _calculatePrice();
                                }
                                : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          FutureBuilder<double>(
            future: BookingLogicService.getPricePerPerson(deviceType: _selectedServiceType!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Text(
                  '$_numberOfPeople game${_numberOfPeople > 1 ? 's' : ''} (${_numberOfPeople * 5} minutes) - 1 game per person',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }
              final pricePerPerson = snapshot.data!;
              final totalPrice = pricePerPerson * _numberOfPeople;
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_numberOfPeople game${_numberOfPeople > 1 ? 's' : ''} (${_numberOfPeople * 5} minutes) - 1 game per person',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Price: Rs ${pricePerPerson.toStringAsFixed(2)} per person × $_numberOfPeople = Rs ${totalPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ] else if (_selectedServiceType == 'Theatre') ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Hours:'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      if (_theatreHours > 1) {
                        setState(() {
                          _theatreHours--;
                        });
                        _calculatePrice();
                      }
                    },
                  ),
                  Text(
                    '$_theatreHours',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      setState(() {
                        _theatreHours++;
                      });
                      _calculatePrice();
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<int>(
            future: _getMaxAvailableForSelectedTime(),
            builder: (context, snapshot) {
              final maxAvailable =
                  snapshot.hasData && snapshot.data! >= 0
                      ? snapshot.data!
                      : (_deviceCapacity > 0 ? _deviceCapacity : 999);

              final maxPeople = maxAvailable > 0 ? maxAvailable : 1;
              if (_theatrePeople > maxPeople && _deviceCapacity > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() {
                    _theatrePeople = maxPeople;
                  });
                });
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Number of People:'),
                      if (_deviceCapacity > 0 && _selectedTimeSlot != null && snapshot.hasData)
                        Text(
                          snapshot.data! >= 0 ? 'Max available: $maxAvailable' : 'Unlimited',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          if (_theatrePeople > 1) {
                            setState(() {
                              _theatrePeople--;
                            });
                            _calculatePrice();
                          }
                        },
                      ),
                      Text(
                        '$_theatrePeople',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              _theatrePeople > maxPeople && _deviceCapacity > 0 ? Colors.red : null,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed:
                            _theatrePeople < maxPeople || _deviceCapacity == 0
                                ? () async {
                                  if (_deviceCapacity > 0 && _selectedTimeSlot != null) {
                                    final available = await _getMaxAvailableForSelectedTime();
                                    if (available < _theatrePeople + 1) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Only $available slot${available > 1 ? 's' : ''} available at selected time. Cannot increase people count.',
                                          ),
                                          backgroundColor: Colors.orange,
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                      return;
                                    }
                                  }
                                  setState(() {
                                    _theatrePeople++;
                                  });
                                  _calculatePrice();
                                }
                                : null,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  // Helper function to convert 24-hour format to 12-hour format
  String _formatTime12Hour(String time24Hour) {
    try {
      final parts = time24Hour.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = parts[1];
        final period = hour >= 12 ? 'PM' : 'AM';
        final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '$hour12:${minute.padLeft(2, '0')} $period';
      }
    } catch (e) {
      // If parsing fails, return original
    }
    return time24Hour;
  }

  // Helper function to convert 12-hour format to 24-hour format
  String _formatTime24Hour(String time12Hour) {
    try {
      final parts = time12Hour.split(' ');
      if (parts.length >= 2) {
        final timePart = parts[0];
        final period = parts[1].toUpperCase();
        final timeParts = timePart.split(':');
        if (timeParts.length >= 2) {
          var hour = int.tryParse(timeParts[0]) ?? 0;
          final minute = timeParts[1];
          if (period == 'PM' && hour != 12) {
            hour += 12;
          } else if (period == 'AM' && hour == 12) {
            hour = 0;
          }
          return '${hour.toString().padLeft(2, '0')}:$minute';
        }
      }
    } catch (e) {
      // If parsing fails, return original
    }
    return time12Hour;
  }

  Widget _buildCapacityInfoSection() {
    if (_deviceCapacity == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Device capacity not configured. Unlimited bookings allowed.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.devices, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Total ${_selectedServiceType} devices: $_deviceCapacity',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotSection() {
    // Time slots in 24-hour format (for internal processing)
    final List<String> _timeSlots24Hour = [
      '09:00',
      '09:30',
      '10:00',
      '10:30',
      '11:00',
      '11:30',
      '12:00',
      '12:30',
      '13:00',
      '13:30',
      '14:00',
      '14:30',
      '15:00',
      '15:30',
      '16:00',
      '16:30',
      '17:00',
      '17:30',
      '18:00',
      '18:30',
      '19:00',
      '19:30',
      '20:00',
      '20:30',
      '21:00',
      '21:30',
      '22:00',
      '22:30',
      '23:00',
      '23:30',
      '24:00',
      '24:30',
    ];

    // Convert to 12-hour format for display
    final List<String> _timeSlots =
        _timeSlots24Hour.map((slot) => _formatTime12Hour(slot)).toList();

    // Preload slots if not already loaded
    if (_deviceCapacity > 0 && _availableSlotsCache.isEmpty && !_loadingSlots) {
      _preloadAvailableSlots();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Time Slot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (_deviceCapacity > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Available slots shown for each time (Total: $_deviceCapacity devices)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _timeSlots.asMap().entries.map((entry) {
                      final index = entry.key;
                      final slot12Hour = entry.value;
                      final slot24Hour = _timeSlots24Hour[index];
                      final isSelected = _selectedTimeSlot == slot12Hour;
                      // Check booked slots using 24-hour format
                      final isBooked = _bookedTimeSlots.contains(slot24Hour);

                      // Check if time slot has passed (only for today's date)
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final selectedDateOnly = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                      );
                      final isToday = selectedDateOnly.isAtSameMomentAs(today);

                      bool isPastTime = false;
                      if (isToday) {
                        // Parse the time slot
                        final slotParts = slot24Hour.split(':');
                        if (slotParts.length == 2) {
                          final slotHour = int.tryParse(slotParts[0]) ?? 0;
                          final slotMinute = int.tryParse(slotParts[1]) ?? 0;
                          final slotDateTime = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            slotHour,
                            slotMinute,
                          );
                          // Disable if slot time has passed (with 1 minute buffer for safety)
                          isPastTime = slotDateTime.isBefore(
                            now.subtract(const Duration(minutes: 1)),
                          );
                        }
                      }

                      // Use cached value if available, otherwise show loading only on initial load
                      final cachedSlots = _availableSlotsCache[slot24Hour];
                      final availableSlots =
                          _deviceCapacity > 0
                              ? (cachedSlots ??
                                  (_loadingSlots ? null : -2)) // -2 means not loaded yet
                              : -1; // -1 means unlimited

                      // Show loading spinner only on initial load, not on every rebuild
                      final isLoading = _deviceCapacity > 0 && cachedSlots == null && _loadingSlots;

                      // Only disable if capacity > 0 AND all slots are booked (availableSlots == 0)
                      // OR if capacity == 0 AND time slot is marked as booked (old behavior)
                      // OR if time slot has passed (for today's date)
                      // availableSlots == -1 means unlimited (capacity == 0)
                      // availableSlots == -2 means not loaded yet (show as available to avoid blocking)
                      final isFullyBooked = _deviceCapacity > 0 ? (availableSlots == 0) : isBooked;
                      final canSelect = !isFullyBooked && !isPastTime;

                      return FilterChip(
                        selected: isSelected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(slot12Hour),
                            if (_deviceCapacity > 0) ...[
                              const SizedBox(width: 4),
                              if (isLoading)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 1.5),
                                )
                              else if (availableSlots != null && availableSlots >= 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        availableSlots > 0
                                            ? Colors.green.shade100
                                            : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$availableSlots',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          availableSlots > 0
                                              ? Colors.green.shade900
                                              : Colors.red.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                        onSelected:
                            isLoading
                                ? null
                                : (canSelect
                                    ? (selected) {
                                      setState(() {
                                        _selectedTimeSlot = selected ? slot12Hour : null;
                                      });
                                    }
                                    : null),
                        disabledColor: Colors.red.shade100,
                        selectedColor: Colors.green.shade300,
                        labelStyle: TextStyle(
                          color:
                              (isFullyBooked || isPastTime)
                                  ? Colors.grey.shade600
                                  : (isSelected ? Colors.white : Colors.black),
                          decoration:
                              (isFullyBooked || isPastTime) ? TextDecoration.lineThrough : null,
                        ),
                        avatar:
                            (isFullyBooked || isPastTime)
                                ? Icon(
                                  isPastTime ? Icons.access_time : Icons.block,
                                  size: 16,
                                  color: isPastTime ? Colors.grey.shade600 : Colors.red.shade700,
                                )
                                : null,
                        tooltip:
                            isPastTime
                                ? 'This time slot has already passed'
                                : isFullyBooked
                                ? _deviceCapacity > 0
                                    ? 'All $_deviceCapacity slots are booked for this time'
                                    : 'This time slot is already booked'
                                : _deviceCapacity > 0
                                ? '$availableSlots of $_deviceCapacity slots available'
                                : 'Available',
                      );
                    }).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          title: const Text('Use Custom Time'),
          value: _useCustomTime,
          onChanged: (value) {
            setState(() {
              _useCustomTime = value ?? false;
              if (!_useCustomTime) {
                _customTime = null;
              }
            });
          },
        ),
        if (_useCustomTime) ...[
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Select Time'),
            subtitle:
                _customTime != null
                    ? FutureBuilder<int>(
                      future:
                          _deviceCapacity > 0 && _selectedServiceType != null
                              ? DeviceCapacityService.getAvailableSlots(
                                deviceType: _selectedServiceType!,
                                date: DateFormat('yyyy-MM-dd').format(_selectedDate),
                                timeSlot:
                                    '${_customTime!.hour.toString().padLeft(2, '0')}:${_customTime!.minute.toString().padLeft(2, '0')}',
                                durationHours:
                                    _selectedServiceType == 'PS4' || _selectedServiceType == 'PS5'
                                        ? _durationHours + (_minutes / 60.0)
                                        : _selectedServiceType == 'Simulator' ||
                                            _selectedServiceType == 'VR'
                                        ? (_numberOfPeople * 5) / 60.0
                                        : _theatreHours.toDouble(),
                              )
                              : Future.value(-1), // -1 means unlimited
                      builder: (context, snapshot) {
                        // For custom time, we still use FutureBuilder since it's dynamic
                        // But cache will help avoid repeated queries
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_customTime!.format(context)),
                              if (_deviceCapacity > 0) ...[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ],
                            ],
                          );
                        }

                        final availableSlots = snapshot.data ?? 0;
                        final timeStr = _customTime!.format(context);

                        if (_deviceCapacity > 0 && snapshot.hasData && availableSlots >= 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(timeStr),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      availableSlots > 0
                                          ? Colors.green.shade100
                                          : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  availableSlots > 0
                                      ? '$availableSlots of $_deviceCapacity slots available'
                                      : 'All $_deviceCapacity slots booked',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        availableSlots > 0
                                            ? Colors.green.shade900
                                            : Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return Text(timeStr);
                      },
                    )
                    : const Text('Tap to select'),
            trailing: const Icon(Icons.access_time),
            onTap: () async {
              // Check if selected date is today
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final selectedDateOnly = DateTime(
                _selectedDate.year,
                _selectedDate.month,
                _selectedDate.day,
              );
              final isToday = selectedDateOnly.isAtSameMomentAs(today);

              // Set initial time to current time if today, otherwise allow any time
              final initialTime =
                  _customTime ?? (isToday ? TimeOfDay.now() : const TimeOfDay(hour: 9, minute: 0));

              final time = await showTimePicker(context: context, initialTime: initialTime);

              if (time != null) {
                // If today, validate that selected time is not in the past
                if (isToday) {
                  final selectedDateTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    time.hour,
                    time.minute,
                  );
                  if (selectedDateTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot select a time that has already passed'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                    return;
                  }
                }

                setState(() {
                  _customTime = time;
                });
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') &&
              _consoleCount > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Price per console:',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                Text(
                  'Rs ${(_calculatedPrice / _consoleCount).toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Console count:', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                Text('$_consoleCount', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              ],
            ),
            const Divider(height: 24),
          ] else if (_selectedServiceType == 'VR' || _selectedServiceType == 'Simulator') ...[
            FutureBuilder<double>(
              future: BookingLogicService.getPricePerPerson(deviceType: _selectedServiceType!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final pricePerPerson = snapshot.data!;
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Price per person (1 game):',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                        Text(
                          'Rs ${pricePerPerson.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Number of people:',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                        Text(
                          '$_numberOfPeople',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total games:',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                        Text(
                          '$_numberOfPeople game${_numberOfPeople > 1 ? 's' : ''} (${_numberOfPeople * 5} minutes)',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                );
              },
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Price:',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Rs ${_calculatedPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
