import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/booking_logic_service.dart';
import 'session_detail_page.dart';
import '../providers/session_provider.dart';

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

  // PS4/PS5 fields
  int _consoleCount = 1;
  int _durationHours = 1;
  int _minutes = 0;
  int _additionalControllers = 0;

  // Theatre fields
  int _theatreHours = 1;
  int _theatrePeople = 1;

  // VR/Simulator fields
  int _durationMinutes = 30;

  // Price calculation
  double _calculatedPrice = 0.0;
  bool _priceCalculated = false;

  // Booked time slots for the selected date and service type
  Set<String> _bookedTimeSlots = {};
  bool _loadingBookedSlots = false;

  // Common scenarios
  List<Map<String, dynamic>> _commonScenarios = [];
  bool _loadingScenarios = true;
  String? _scenariosError;

  final List<String> _serviceTypes = ['PS5', 'PS4', 'VR', 'Simulator', 'Theatre'];

  @override
  void initState() {
    super.initState();
    _selectedServiceType = widget.serviceType ?? 'PS5';
    _calculatePrice();
    _loadBookedTimeSlots();
    _loadCommonScenarios();
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

  // Load booked time slots for the selected date and service type
  Future<void> _loadBookedTimeSlots() async {
    if (_selectedServiceType == null) return;

    setState(() {
      _loadingBookedSlots = true;
    });

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

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

          // Mark all time slots that overlap with this booking
          for (var slot in _timeSlots) {
            final slot24Hour = _formatTime24Hour(slot);
            final slotParts = slot24Hour.split(':');
            if (slotParts.length == 2) {
              final slotHour = int.tryParse(slotParts[0]) ?? 0;
              final slotMinute = int.tryParse(slotParts[1]) ?? 0;
              final slotDecimal = slotHour + (slotMinute / 60.0);
              final slotEndDecimal = slotDecimal + 1.0; // Each slot is 1 hour

              // Check if slot overlaps with booking
              if ((slotDecimal >= startDecimal && slotDecimal < endDecimal) ||
                  (slotEndDecimal > startDecimal && slotEndDecimal <= endDecimal) ||
                  (slotDecimal <= startDecimal && slotEndDecimal >= endDecimal)) {
                bookedSlots.add(slot);
              }
            }
          }
        }
      }

      // Also check active sessions
      final activeSessionsSnapshot =
          await _firestore.collection('active_sessions').where('status', isEqualTo: 'active').get();

      for (var sessionDoc in activeSessionsSnapshot.docs) {
        final sessionData = sessionDoc.data();
        final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

        for (var service in services) {
          final serviceType = service['type'] as String? ?? '';
          if (serviceType != _selectedServiceType) continue;

          final startTimeStr = service['startTime'] as String?;
          if (startTimeStr == null) continue;

          try {
            final startTime = DateTime.parse(startTimeStr);
            final serviceDateId = DateFormat('yyyy-MM-dd').format(startTime);

            // Only check for the same date
            if (serviceDateId != dateId) continue;

            final hours = (service['hours'] as num?)?.toInt() ?? 0;
            final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
            final serviceDuration = hours + (minutes / 60.0);

            final serviceStartDecimal = startTime.hour + (startTime.minute / 60.0);
            final serviceEndDecimal = serviceStartDecimal + serviceDuration;

            // Mark all time slots that overlap with this active session
            for (var slot in _timeSlots) {
              final slot24Hour = _formatTime24Hour(slot);
              final slotParts = slot24Hour.split(':');
              if (slotParts.length == 2) {
                final slotHour = int.tryParse(slotParts[0]) ?? 0;
                final slotMinute = int.tryParse(slotParts[1]) ?? 0;
                final slotDecimal = slotHour + (slotMinute / 60.0);
                final slotEndDecimal = slotDecimal + 1.0;

                // Check if slot overlaps with active session
                if ((slotDecimal >= serviceStartDecimal && slotDecimal < serviceEndDecimal) ||
                    (slotEndDecimal > serviceStartDecimal && slotEndDecimal <= serviceEndDecimal) ||
                    (slotDecimal <= serviceStartDecimal && slotEndDecimal >= serviceEndDecimal)) {
                  bookedSlots.add(slot);
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing active session time: $e');
            continue;
          }
        }
      }

      setState(() {
        _bookedTimeSlots = bookedSlots;
        _loadingBookedSlots = false;
      });
    } catch (e) {
      debugPrint('Error loading booked time slots: $e');
      setState(() {
        _loadingBookedSlots = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Time slots (every hour from 9 AM to 11 PM) in 12-hour format
  List<String> get _timeSlots {
    return List.generate(15, (index) {
      final hour = 9 + index;
      final hour24 = hour.toString().padLeft(2, '0');
      return _formatTime12Hour('$hour24:00');
    });
  }

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

  Future<void> _calculatePrice() async {
    if (_selectedServiceType == null) return;

    setState(() {
      _priceCalculated = false;
    });

    try {
      double price = 0.0;

      if (_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') {
        // Calculate price for one console
        final singleConsolePrice = await BookingLogicService.calculateBookingPrice(
          deviceType: _selectedServiceType!,
          hours: _durationHours,
          minutes: _minutes,
          additionalControllers: _additionalControllers,
        );
        // Multiply by console count
        price = singleConsolePrice * _consoleCount;
      } else if (_selectedServiceType == 'VR' || _selectedServiceType == 'Simulator') {
        price = await BookingLogicService.calculateBookingPrice(
          deviceType: _selectedServiceType!,
          hours: _durationMinutes ~/ 60,
          minutes: _durationMinutes % 60,
        );
      } else if (_selectedServiceType == 'Theatre') {
        price = await BookingLogicService.calculateBookingPrice(
          deviceType: _selectedServiceType!,
          hours: _theatreHours,
          minutes: 0,
          people: _theatrePeople,
        );
      }

      setState(() {
        _calculatedPrice = price;
        _priceCalculated = true;
      });
    } catch (e) {
      debugPrint('Error calculating price: $e');
      setState(() {
        _priceCalculated = false;
      });
    }
  }

  Future<void> _createBooking() async {
    // Validate inputs
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name'), backgroundColor: Colors.red),
      );
      return;
    }

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

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(widget.selectedDate);

      // Convert time slot to 24-hour format
      String timeSlot24Hour;
      if (_useCustomTime && _customTime != null) {
        final hour = _customTime!.hour.toString().padLeft(2, '0');
        final minute = _customTime!.minute.toString().padLeft(2, '0');
        timeSlot24Hour = '$hour:$minute';
      } else {
        timeSlot24Hour = _formatTime24Hour(_selectedTimeSlot!);
      }

      // Calculate duration
      double durationHours;
      if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR') {
        durationHours = _durationMinutes / 60.0;
      } else if (_selectedServiceType == 'Theatre') {
        durationHours = _theatreHours.toDouble();
      } else {
        durationHours = _durationHours + (_minutes / 60.0);
      }

      // Check for conflicts
      final hasConflict = await BookingLogicService.hasTimeConflict(
        deviceType: _selectedServiceType!,
        date: dateId,
        timeSlot: timeSlot24Hour,
        durationHours: durationHours,
      );

      if (hasConflict) {
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time slot conflicts with an existing booking or active session'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Create booking data
      final bookingData = {
        'serviceType': _selectedServiceType,
        'date': dateId,
        'dateTimestamp': Timestamp.fromDate(widget.selectedDate),
        'timeSlot': timeSlot24Hour,
        'durationHours': durationHours,
        'customerName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        if (_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4')
          'consoleCount': _consoleCount,
        if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR')
          'durationMinutes': _durationMinutes,
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
      _consoleCount = count;
      _durationHours = hours;
      _minutes = minutes;
      _additionalControllers = additionalControllers;
      _selectedTimeSlot = null; // Reset time slot when applying scenario
    });
    _calculatePrice();
    _loadBookedTimeSlots(); // Reload booked slots for the new service type
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
                    'Error loading Quick Add scenarios',
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
                'Quick Add - No scenarios configured',
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
                  'Quick Add (${_commonScenarios.length})',
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
          // Quick Access: Active Sessions
          const _QuickAccessSection(key: ValueKey('quick_access_section')),

          const Divider(),

          // Quick Add Section - Common Scenarios from Admin
          _buildQuickAddSection(),

          const Divider(),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Information
                  _buildCustomerInfoSection(),

                  const SizedBox(height: 24),

                  // Service Type Selection
                  _buildServiceTypeSection(),

                  const SizedBox(height: 24),

                  // Service-specific configuration
                  _buildServiceConfigSection(),

                  const SizedBox(height: 24),

                  // Time Slot Selection
                  _buildTimeSlotSection(),

                  const SizedBox(height: 24),

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
                  icon: const Icon(Icons.check_circle, size: 24),
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

  Widget _buildCustomerInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTypeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
        ),
      ),
    );
  }

  // Reload booked slots when service type changes
  void _onServiceTypeChanged(String? newType) {
    setState(() {
      _selectedServiceType = newType;
      _selectedTimeSlot = null; // Reset time slot selection
    });
    _calculatePrice();
    _loadBookedTimeSlots();
  }

  Widget _buildServiceConfigSection() {
    if (_selectedServiceType == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_selectedServiceType} Configuration',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') ...[
              _buildConsoleConfig(),
            ] else if (_selectedServiceType == 'Theatre') ...[
              _buildTheatreConfig(),
            ] else if (_selectedServiceType == 'VR' || _selectedServiceType == 'Simulator') ...[
              _buildVrSimulatorConfig(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsoleConfig() {
    return Column(
      children: [
        // Console Count
        Row(
          children: [
            const Text('Console Count: '),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                if (_consoleCount > 1) {
                  setState(() {
                    _consoleCount--;
                    _calculatePrice();
                  });
                }
              },
            ),
            Text(
              '$_consoleCount',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                setState(() {
                  _consoleCount++;
                  _calculatePrice();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Duration Hours
        Row(
          children: [
            const Text('Hours: '),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                if (_durationHours > 0) {
                  setState(() {
                    _durationHours--;
                    _calculatePrice();
                  });
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
                  _calculatePrice();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Minutes
        Row(
          children: [
            const Text('Minutes: '),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                if (_minutes >= 15) {
                  setState(() {
                    _minutes -= 15;
                    _calculatePrice();
                  });
                }
              },
            ),
            Text('$_minutes', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                setState(() {
                  _minutes += 15;
                  if (_minutes >= 60) {
                    _durationHours += _minutes ~/ 60;
                    _minutes = _minutes % 60;
                  }
                  _calculatePrice();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Additional Controllers
        Row(
          children: [
            const Text('Additional Controllers: '),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                if (_additionalControllers > 0) {
                  setState(() {
                    _additionalControllers--;
                    _calculatePrice();
                  });
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
                  _calculatePrice();
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTheatreConfig() {
    return Column(
      children: [
        Row(
          children: [
            const Text('Hours: '),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                if (_theatreHours > 1) {
                  setState(() {
                    _theatreHours--;
                    _calculatePrice();
                  });
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
                if (_theatreHours < 4) {
                  setState(() {
                    _theatreHours++;
                    _calculatePrice();
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Number of People: '),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () {
                if (_theatrePeople > 1) {
                  setState(() {
                    _theatrePeople--;
                    _calculatePrice();
                  });
                }
              },
            ),
            Text(
              '$_theatrePeople',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () {
                setState(() {
                  _theatrePeople++;
                  _calculatePrice();
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVrSimulatorConfig() {
    return Row(
      children: [
        const Text('Duration (minutes): '),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () {
            if (_durationMinutes >= 5) {
              setState(() {
                _durationMinutes -= 5;
                _calculatePrice();
              });
            }
          },
        ),
        Text(
          '$_durationMinutes',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () {
            setState(() {
              _durationMinutes += 5;
              _calculatePrice();
            });
          },
        ),
      ],
    );
  }

  Widget _buildTimeSlotSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Time Slot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Use Custom Time'),
                    value: _useCustomTime,
                    onChanged: (value) {
                      setState(() {
                        _useCustomTime = value;
                        if (!value) {
                          _customTime = null;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            if (!_useCustomTime) ...[
              const SizedBox(height: 8),
              if (_loadingBookedSlots)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _timeSlots.map((slot) {
                        final isSelected = _selectedTimeSlot == slot;
                        final isBooked = _bookedTimeSlots.contains(slot);

                        return FilterChip(
                          selected: isSelected,
                          label: Text(slot),
                          onSelected:
                              isBooked
                                  ? null
                                  : (selected) {
                                    setState(() {
                                      _selectedTimeSlot = selected ? slot : null;
                                    });
                                  },
                          disabledColor: Colors.red.shade100,
                          labelStyle: TextStyle(
                            color:
                                isBooked
                                    ? Colors.red.shade700
                                    : (isSelected ? Colors.white : Colors.black),
                            decoration: isBooked ? TextDecoration.lineThrough : null,
                          ),
                          avatar:
                              isBooked
                                  ? Icon(Icons.block, size: 16, color: Colors.red.shade700)
                                  : null,
                          tooltip: isBooked ? 'This time slot is already booked' : null,
                        );
                      }).toList(),
                ),
            ] else ...[
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Select Time'),
                subtitle: Text(
                  _customTime != null ? _customTime!.format(context) : 'Tap to select',
                ),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: _customTime ?? TimeOfDay.now(),
                  );
                  if (time != null) {
                    setState(() {
                      _customTime = time;
                    });
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSection() {
    // Calculate single console price for display
    double singleConsolePrice = 0.0;
    if ((_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') && _consoleCount > 1) {
      singleConsolePrice = _calculatedPrice / _consoleCount;
    }

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    'Rs ${singleConsolePrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Console count:',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  Text(
                    '$_consoleCount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
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
      ),
    );
  }
}

/// Quick Access Section - Shows active sessions for devices
class _QuickAccessSection extends StatelessWidget {
  const _QuickAccessSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Query all active_sessions and filter in code to handle case variations
    // Use a key to prevent unnecessary rebuilds
    return StreamBuilder<QuerySnapshot>(
      key: const ValueKey('quick_access_stream'),
      stream: FirebaseFirestore.instance.collection('active_sessions').snapshots(),
      builder: (context, snapshot) {
        // Show loading indicator while fetching
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200, width: 1),
            ),
            child: const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        // Handle errors
        if (snapshot.hasError) {
          debugPrint('Error loading active sessions: ${snapshot.error}');
          return const SizedBox.shrink();
        }

        // Check if we have data
        if (!snapshot.hasData) {
          debugPrint('Quick Access: No snapshot data');
          return const SizedBox.shrink();
        }

        if (snapshot.data!.docs.isEmpty) {
          debugPrint('Quick Access: No active sessions found in Firestore');
          return const SizedBox.shrink();
        }

        debugPrint('Quick Access: Found ${snapshot.data!.docs.length} active session(s)');

        // Group sessions by device type (deduplicate by sessionId + deviceType)
        final Map<String, List<Map<String, dynamic>>> sessionsByDevice = {};
        final Set<String> processedSessions =
            {}; // Track processed sessionId+deviceType combinations

        for (var doc in snapshot.data!.docs) {
          try {
            final sessionData = doc.data() as Map<String, dynamic>;
            final status = sessionData['status'] as String? ?? '';

            debugPrint('Quick Access: Processing session ${doc.id}, status: $status');

            // Only process active sessions
            if (status.toLowerCase() != 'active') {
              debugPrint('Quick Access: Skipping session ${doc.id} - status is not active');
              continue;
            }

            final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);

            debugPrint('Quick Access: Session ${doc.id} has ${services.length} service(s)');

            // If no services, skip this session
            if (services.isEmpty) {
              debugPrint('Quick Access: Skipping session ${doc.id} - no services');
              continue;
            }

            // Track unique device types per session to avoid duplicates
            final Set<String> deviceTypesInSession = {};

            for (var service in services) {
              final deviceType = service['type'] as String? ?? '';
              if (deviceType.isEmpty) {
                debugPrint('Quick Access: Service has no type');
                continue;
              }

              // Create unique key for this session+device combination
              final uniqueKey = '${doc.id}_$deviceType';

              // Skip if we've already processed this combination
              if (processedSessions.contains(uniqueKey)) {
                debugPrint('Quick Access: Skipping duplicate $deviceType session ${doc.id}');
                continue;
              }

              // Skip if we've already added this device type for this session
              if (deviceTypesInSession.contains(deviceType)) {
                debugPrint(
                  'Quick Access: Skipping duplicate device type $deviceType in session ${doc.id}',
                );
                continue;
              }

              // Mark as processed
              processedSessions.add(uniqueKey);
              deviceTypesInSession.add(deviceType);

              if (!sessionsByDevice.containsKey(deviceType)) {
                sessionsByDevice[deviceType] = [];
              }

              sessionsByDevice[deviceType]!.add({
                'sessionId': doc.id,
                'sessionData': sessionData,
                'service': service,
              });

              debugPrint('Quick Access: Added $deviceType session ${doc.id}');
            }
          } catch (e) {
            debugPrint('Quick Access: Error processing session ${doc.id}: $e');
            continue;
          }
        }

        debugPrint('Quick Access: Grouped into ${sessionsByDevice.length} device type(s)');

        // If no sessions found, show empty state
        if (sessionsByDevice.isEmpty) {
          debugPrint('Quick Access: No sessions grouped by device type');
          // Still show the section but with empty message
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.flash_on, size: 18, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Quick Access - No active sessions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        debugPrint(
          'Quick Access: Showing Quick Access section with ${sessionsByDevice.length} device type(s)',
        );

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.flash_on, size: 18, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Quick Access - Active Sessions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...sessionsByDevice.entries.map((entry) {
                final deviceType = entry.key;
                final sessions = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _QuickAccessCard(deviceType: deviceType, sessions: sessions),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final String deviceType;
  final List<Map<String, dynamic>> sessions;

  const _QuickAccessCard({required this.deviceType, required this.sessions});

  @override
  Widget build(BuildContext context) {
    final session = sessions.first;
    final sessionData = session['sessionData'] as Map<String, dynamic>;
    final service = session['service'] as Map<String, dynamic>;
    final sessionId = session['sessionId'] as String;
    final customerName = sessionData['customerName'] as String? ?? 'Customer';

    // Calculate time remaining
    String timeRemaining = '';
    try {
      final startTimeStr = service['startTime'] as String?;
      if (startTimeStr != null) {
        final startTime = DateTime.parse(startTimeStr);
        final hours = (service['hours'] as num?)?.toInt() ?? 0;
        final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
        final endTime = startTime.add(Duration(hours: hours, minutes: minutes));
        final now = DateTime.now();
        final remaining = endTime.difference(now);

        if (remaining.isNegative) {
          timeRemaining = 'Time expired';
        } else {
          final remainingHours = remaining.inHours;
          final remainingMinutes = remaining.inMinutes % 60;
          if (remainingHours > 0) {
            timeRemaining = '${remainingHours}h ${remainingMinutes}m left';
          } else {
            timeRemaining = '${remainingMinutes}m left';
          }
        }
      }
    } catch (e) {
      timeRemaining = 'Active';
    }

    Color deviceColor;
    IconData deviceIcon;
    switch (deviceType) {
      case 'PS5':
        deviceColor = Colors.blue;
        deviceIcon = Icons.sports_esports;
        break;
      case 'PS4':
        deviceColor = Colors.purple;
        deviceIcon = Icons.videogame_asset;
        break;
      default:
        deviceColor = Colors.grey;
        deviceIcon = Icons.devices;
    }

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () async {
          await context.read<SessionProvider>().loadSession(sessionId);
          if (context.mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionDetailPage()));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: deviceColor,
                child: Icon(deviceIcon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$deviceType - $customerName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeRemaining,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
