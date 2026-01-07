import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'device_selection_page.dart';
import '../providers/session_provider.dart';
import '../services/booking_logic_service.dart';
import 'session_detail_page.dart';
import 'create_booking_page.dart';

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedServiceType;
  DateTime _selectedDate = DateTime.now();
  DateTime _historyFilterDate =
      DateTime.now(); // Date filter for history tab (initially current date)
  String? _selectedTimeSlot;
  bool _useCustomTime = false; // Toggle for custom time selection
  TimeOfDay? _customTime; // Selected custom time
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  int _consoleCount = 1; // For PS5/PS4
  int _theatreHours = 1; // For Theatre
  int _theatrePeople = 1; // For Theatre
  int _durationHours = 1; // Duration in hours for PS5/PS4
  int _durationMinutes = 30; // Duration in minutes for Simulator/VR
  late TabController _tabController;

  final List<String> _serviceTypes = [
    'PS5',
    'PS4',
    'VR',
    'Simulator',
    'Theatre',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

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

  // Helper function to convert 12-hour time string back to 24-hour for storage
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

  // Time slots (every hour from 9 AM to 11 PM) in 12-hour format
  List<String> get _timeSlots {
    return List.generate(15, (index) {
      final hour = 9 + index;
      final hour24 = hour.toString().padLeft(2, '0');
      return _formatTime12Hour('$hour24:00');
    });
  }


  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Get pending bookings stream - only shows pending/confirmed bookings (not done/cancelled)
  Stream<QuerySnapshot> _getPendingBookingsStream(String dateId) {
    final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isPastDate = dateId.compareTo(todayId) < 0;

    if (isPastDate) {
      // For past dates, return empty (past bookings should be in completed)
      return _firestore
          .collection('bookings')
          .where('date', isEqualTo: dateId)
          .where('status', whereIn: ['nonexistent']) // Return empty
          .snapshots();
    } else {
      // For today and future dates, only show pending and confirmed bookings
      return _firestore
          .collection('bookings')
          .where('date', isEqualTo: dateId)
          .where('status', whereIn: ['pending', 'confirmed'])
          .snapshots();
    }
  }

  Future<void> _checkAvailability(String serviceType, DateTime date) async {
    setState(() {
      _selectedServiceType = serviceType;
      _selectedDate = date;
    });

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(date);
      final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isPastDate = dateId.compareTo(todayId) < 0;

      // For past dates, check history; for today/future, check active bookings
      QuerySnapshot bookingsSnapshot;
      if (isPastDate) {
        bookingsSnapshot =
            await _firestore
                .collection('booking_history')
                .where('date', isEqualTo: dateId)
                .where('serviceType', isEqualTo: serviceType)
                .get();
      } else {
        bookingsSnapshot =
            await _firestore
                .collection('bookings')
                .where('date', isEqualTo: dateId)
                .where('serviceType', isEqualTo: serviceType)
                .get();
      }

      // Show availability dialog
      if (mounted) {
        _showAvailabilityDialog(serviceType, date, bookingsSnapshot.docs);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking availability: $e')),
        );
      }
    }
  }

  void _showAvailabilityDialog(
    String serviceType,
    DateTime date,
    List<QueryDocumentSnapshot> bookings,
  ) {
    // Helper function to calculate booked slots from bookings list
    Set<String> calculateBookedSlots(List<QueryDocumentSnapshot> bookingsList) {
      final Set<String> slots = {};
      for (var doc in bookingsList) {
        final data = doc.data() as Map<String, dynamic>;
        final timeSlot = data['timeSlot'] as String? ?? '';
        final durationHours =
            (data['durationHours'] as num?)?.toDouble() ?? 1.0;
        final status =
            (data['status'] as String? ?? 'pending').toLowerCase().trim();

        // Skip if no time slot
        if (timeSlot.isEmpty) continue;

        // IMPORTANT: Block time slots for 'pending', 'confirmed', and 'done' bookings
        // Only 'cancelled' bookings should NOT block (time slots become available/green)
        if (status == 'cancelled') {
          continue; // Skip - don't add to bookedSlots, so it shows as available (green)
        }

        // Parse time slot (e.g., "14:00") and convert to 12-hour format for display
        final parts = timeSlot.split(':');
        if (parts.length == 2) {
          final startHour = int.tryParse(parts[0]) ?? 0;
          // Use ceil to round up - if booking is 30 minutes (0.5 hours), mark the hour as booked
          final durationHoursRounded = durationHours.ceil();
          // Mark all slots within the duration as booked
          for (int i = 0; i < durationHoursRounded; i++) {
            final hour = startHour + i;
            if (hour <= 23) {
              final slot24Hour = '${hour.toString().padLeft(2, '0')}:00';
              // Convert to 12-hour format for comparison with displayed slots
              final slot12Hour = _formatTime12Hour(slot24Hour);
              slots.add(slot12Hour);
            }
          }
        }
      }
      return slots;
    }

    // Initialize booked slots
    final Set<String> initialBookedSlots = calculateBookedSlots(bookings);
    DateTime dialogSelectedDate = date;
    final Set<String> dialogBookedSlots = Set<String>.from(initialBookedSlots);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              // Function to reload availability for a new date
              Future<void> reloadAvailability(DateTime selectedDate) async {
                try {
                  final dateId = DateFormat('yyyy-MM-dd').format(selectedDate);
                  final todayId = DateFormat(
                    'yyyy-MM-dd',
                  ).format(DateTime.now());
                  final isPastDate = dateId.compareTo(todayId) < 0;

                  // For past dates, check history; for today/future, check active bookings
                  QuerySnapshot bookingsSnapshot;
                  if (isPastDate) {
                    bookingsSnapshot =
                        await _firestore
                            .collection('booking_history')
                            .where('date', isEqualTo: dateId)
                            .where('serviceType', isEqualTo: serviceType)
                            .get();
                  } else {
                    bookingsSnapshot =
                        await _firestore
                            .collection('bookings')
                            .where('date', isEqualTo: dateId)
                            .where('serviceType', isEqualTo: serviceType)
                            .get();
                  }

                  // Calculate new booked slots
                  final newBookedSlots = calculateBookedSlots(
                    bookingsSnapshot.docs,
                  );

                  setDialogState(() {
                    dialogBookedSlots.clear();
                    dialogBookedSlots.addAll(newBookedSlots);
                    dialogSelectedDate = selectedDate;
                  });
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error loading availability: $e')),
                    );
                  }
                }
              }

              return AlertDialog(
                title: Text(
                  '$serviceType Availability - ${DateFormat('MMM dd, yyyy').format(dialogSelectedDate)}',
                ),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Picker
                        Text(
                          'Select Date:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final maxDate = now.add(const Duration(days: 30));

                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dialogSelectedDate,
                              firstDate: now,
                              lastDate: maxDate,
                              selectableDayPredicate: (date) {
                                return date.isAfter(
                                      now.subtract(const Duration(days: 1)),
                                    ) &&
                                    date.isBefore(
                                      maxDate.add(const Duration(days: 1)),
                                    );
                              },
                            );

                            if (picked != null &&
                                picked != dialogSelectedDate) {
                              await reloadAvailability(picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: Colors.purple.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(dialogSelectedDate),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.purple.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Available Time Slots:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.purple.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children:
                              _timeSlots.map((slot) {
                                final isBooked = dialogBookedSlots.contains(
                                  slot,
                                );
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isBooked
                                            ? Colors.red.shade50
                                            : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          isBooked
                                              ? Colors.red.shade300
                                              : Colors.green.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isBooked ? Icons.close : Icons.check,
                                        size: 14,
                                        color:
                                            isBooked
                                                ? Colors.red
                                                : Colors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        slot,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color:
                                              isBooked
                                                  ? Colors.red.shade700
                                                  : Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showBookingDialog(String serviceType, DateTime date) async {
    _selectedServiceType = serviceType;
    _selectedDate = date;
    _selectedTimeSlot = null;
    _useCustomTime = false;
    _customTime = null;
    _nameController.clear();
    _phoneController.clear();
    _consoleCount = 1;
    _theatreHours = 1;
    _theatrePeople = 1;
    _durationHours = 1;
    _durationMinutes = 30;

    // Get existing bookings for this date and service type
    final dateId = DateFormat('yyyy-MM-dd').format(date);
    final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isPastDate = dateId.compareTo(todayId) < 0;

    // For past dates, check history; for today/future, check active bookings
    QuerySnapshot existingBookings;
    if (isPastDate) {
      // Check booking history for past dates
      existingBookings =
          await _firestore
              .collection('booking_history')
              .where('date', isEqualTo: dateId)
              .where('serviceType', isEqualTo: serviceType)
              .get();
    } else {
      // Check active bookings for today and future dates
      existingBookings =
          await _firestore
              .collection('bookings')
              .where('date', isEqualTo: dateId)
              .where('serviceType', isEqualTo: serviceType)
              .get();
    }

    // Calculate booked slots considering duration
    final Set<String> bookedSlots = {};
    for (var doc in existingBookings.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final timeSlot = data['timeSlot'] as String? ?? '';
      final durationHours = (data['durationHours'] as num?)?.toDouble() ?? 1.0;
      final status =
          (data['status'] as String? ?? 'pending').toLowerCase().trim();

      // Skip if no time slot
      if (timeSlot.isEmpty) continue;

      // IMPORTANT: Block time slots for 'pending', 'confirmed', and 'done' bookings
      // Only 'cancelled' bookings should NOT block (time slots become available/green)
      // Once a booking is made, it blocks the slot regardless of pending/done status
      if (status == 'cancelled') {
        continue; // Skip - don't add to bookedSlots, so it shows as available (green)
      }
      // 'pending', 'confirmed', and 'done' bookings will block the time slot (red)

      final parts = timeSlot.split(':');
      if (parts.length == 2) {
        final startHour = int.tryParse(parts[0]) ?? 0;
        // Use ceil to round up - if booking is 30 minutes (0.5 hours), mark the hour as booked
        final durationHoursRounded = durationHours.ceil();
        for (int i = 0; i < durationHoursRounded; i++) {
          final hour = startHour + i;
          if (hour <= 23) {
            final slot24Hour = '${hour.toString().padLeft(2, '0')}:00';
            // Convert to 12-hour format for comparison with displayed slots
            final slot12Hour = _formatTime12Hour(slot24Hour);
            bookedSlots.add(slot12Hour);
          }
        }
      }
    }

    if (!mounted) return;

    // Store selected date for the dialog (can be changed)
    DateTime dialogSelectedDate = date;
    // Initialize booked slots outside builder to persist across rebuilds
    final Set<String> dialogBookedSlots = Set<String>.from(bookedSlots);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              // Function to reload booked slots when date changes
              Future<void> reloadBookedSlots(DateTime selectedDate) async {
                final dateId = DateFormat('yyyy-MM-dd').format(selectedDate);
                final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
                final isPastDate = dateId.compareTo(todayId) < 0;

                QuerySnapshot existingBookings;
                if (isPastDate) {
                  existingBookings =
                      await _firestore
                          .collection('booking_history')
                          .where('date', isEqualTo: dateId)
                          .where('serviceType', isEqualTo: serviceType)
                          .get();
                } else {
                  existingBookings =
                      await _firestore
                          .collection('bookings')
                          .where('date', isEqualTo: dateId)
                          .where('serviceType', isEqualTo: serviceType)
                          .get();
                }

                final Set<String> newBookedSlots = {};
                for (var doc in existingBookings.docs) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null) continue;

                  final timeSlot = data['timeSlot'] as String? ?? '';
                  final durationHours =
                      (data['durationHours'] as num?)?.toDouble() ?? 1.0;
                  final status =
                      (data['status'] as String? ?? 'pending')
                          .toLowerCase()
                          .trim();

                  if (timeSlot.isEmpty) continue;
                  if (status == 'cancelled') continue;

                  final parts = timeSlot.split(':');
                  if (parts.length == 2) {
                    final startHour = int.tryParse(parts[0]) ?? 0;
                    final durationHoursRounded = durationHours.ceil();
                    for (int i = 0; i < durationHoursRounded; i++) {
                      final hour = startHour + i;
                      if (hour <= 23) {
                        final slot24Hour =
                            '${hour.toString().padLeft(2, '0')}:00';
                        // Convert to 12-hour format for comparison with displayed slots
                        final slot12Hour = _formatTime12Hour(slot24Hour);
                        newBookedSlots.add(slot12Hour);
                      }
                    }
                  }
                }

                setDialogState(() {
                  // Update the persisted set
                  dialogBookedSlots.clear();
                  dialogBookedSlots.addAll(newBookedSlots);
                  dialogSelectedDate = selectedDate;
                  _selectedTimeSlot = null; // Clear selection when date changes
                });
              }

              // Form key for validation
              final formKey = GlobalKey<FormState>();

              return Dialog(
                insetPadding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Book $serviceType',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Date Picker
                          Text(
                            'Select Date:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final maxDate = now.add(const Duration(days: 30));

                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dialogSelectedDate,
                                firstDate: now,
                                lastDate: maxDate,
                                selectableDayPredicate: (date) {
                                  return date.isAfter(
                                        now.subtract(const Duration(days: 1)),
                                      ) &&
                                      date.isBefore(
                                        maxDate.add(const Duration(days: 1)),
                                      );
                                },
                              );

                              if (picked != null &&
                                  picked != dialogSelectedDate) {
                                // Update global selected date
                                _selectedDate = picked;
                                // Reload booked slots for the new date (this will update dialogSelectedDate and clear selection)
                                await reloadBookedSlots(picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.purple.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    color: Colors.purple.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(dialogSelectedDate),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.purple.shade700,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Custom Time Toggle
                          Row(
                            children: [
                              Switch(
                                value: _useCustomTime,
                                onChanged: (value) {
                                  setDialogState(() {
                                    _useCustomTime = value;
                                    if (value) {
                                      // Clear regular time slot selection when enabling custom time
                                      _selectedTimeSlot = null;
                                      // Initialize custom time to current time if not set
                                      _customTime ??= TimeOfDay.now();
                                    } else {
                                      // Clear custom time when disabling
                                      _customTime = null;
                                    }
                                  });
                                },
                                activeColor: Colors.purple.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Use Custom Time',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Custom Time Picker (shown when toggle is enabled)
                          if (_useCustomTime) ...[
                            Text(
                              'Select Custom Time:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _customTime ?? TimeOfDay.now(),
                                  builder: (context, child) {
                                    return MediaQuery(
                                      data: MediaQuery.of(
                                        context,
                                      ).copyWith(alwaysUse24HourFormat: false),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    _customTime = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.purple.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      color: Colors.purple.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _customTime != null
                                          ? _customTime!.format(context)
                                          : 'Select Time',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color: Colors.purple.shade700,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Time Slot Selection (shown when custom time is disabled)
                          if (!_useCustomTime) ...[
                            Text(
                              'Select Time Slot:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  _timeSlots.map((slot) {
                                    final isBooked = dialogBookedSlots.contains(
                                      slot,
                                    );
                                    final isSelected =
                                        _selectedTimeSlot == slot;
                                    return GestureDetector(
                                      onTap:
                                          isBooked
                                              ? null
                                              : () {
                                                setDialogState(() {
                                                  _selectedTimeSlot =
                                                      isSelected ? null : slot;
                                                });
                                              },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              isBooked
                                                  ? Colors.red.shade50
                                                  : isSelected
                                                  ? Colors.purple.shade300
                                                  : Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color:
                                                isBooked
                                                    ? Colors.red.shade300
                                                    : isSelected
                                                    ? Colors.purple.shade700
                                                    : Colors.green.shade300,
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isBooked
                                                  ? Icons.close
                                                  : Icons.check,
                                              size: 14,
                                              color:
                                                  isBooked
                                                      ? Colors.red
                                                      : isSelected
                                                      ? Colors.white
                                                      : Colors.green,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              slot,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                                color:
                                                    isBooked
                                                        ? Colors.red.shade700
                                                        : isSelected
                                                        ? Colors.white
                                                        : Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ],
                          const SizedBox(height: 20),
                          // Customer Name
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                              helperText: 'Enter customer full name',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Customer name is required';
                              }
                              if (value.trim().length < 2) {
                                return 'Name must be at least 2 characters';
                              }
                              return null;
                            },
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 16),
                          // Phone Number
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone),
                              helperText: 'Enter 10-digit phone number',
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Phone number is required';
                              }
                              // Remove spaces, dashes, and parentheses for validation
                              final phoneDigits = value.replaceAll(
                                RegExp(r'[\s\-\(\)]'),
                                '',
                              );
                              if (phoneDigits.length < 10) {
                                return 'Phone number must be at least 10 digits';
                              }
                              if (!RegExp(r'^[0-9]+$').hasMatch(phoneDigits)) {
                                return 'Phone number must contain only digits';
                              }
                              return null;
                            },
                            maxLength: 10,
                          ),
                          const SizedBox(height: 16),
                          // Service-specific fields
                          if (serviceType == 'PS5' || serviceType == 'PS4') ...[
                            // Duration Selection (for PS5/PS4)
                            Text(
                              'Duration (Hours):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (_durationHours > 1) {
                                      setDialogState(() => _durationHours--);
                                    }
                                  },
                                ),
                                Container(
                                  width: 60,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$_durationHours',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    if (_durationHours < 8) {
                                      setDialogState(() => _durationHours++);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Number of Consoles:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (_consoleCount > 1) {
                                      setDialogState(() => _consoleCount--);
                                    }
                                  },
                                ),
                                Container(
                                  width: 60,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$_consoleCount',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    setDialogState(() => _consoleCount++);
                                  },
                                ),
                              ],
                            ),
                          ] else if (serviceType == 'Simulator' ||
                              serviceType == 'VR') ...[
                            // Duration Selection (for Simulator/VR in minutes)
                            Text(
                              'Duration (Minutes):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (_durationMinutes > 15) {
                                      setDialogState(
                                        () => _durationMinutes -= 15,
                                      );
                                    }
                                  },
                                ),
                                Container(
                                  width: 80,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$_durationMinutes min',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    if (_durationMinutes < 240) {
                                      setDialogState(
                                        () => _durationMinutes += 15,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ] else if (serviceType == 'Theatre') ...[
                            Text(
                              'Hours:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (_theatreHours > 1) {
                                      setDialogState(() => _theatreHours--);
                                    }
                                  },
                                ),
                                Container(
                                  width: 60,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$_theatreHours',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    if (_theatreHours < 4) {
                                      setDialogState(() => _theatreHours++);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Total People:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (_theatrePeople > 1) {
                                      setDialogState(() => _theatrePeople--);
                                    }
                                  },
                                ),
                                Container(
                                  width: 60,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$_theatrePeople',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    setDialogState(() => _theatrePeople++);
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 24),
                          // Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  // Validate form before creating booking
                                  if (formKey.currentState!.validate()) {
                                    // Update global selected date before creating booking
                                    _selectedDate = dialogSelectedDate;
                                    _createBooking(context);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade700,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Confirm Booking'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _createBooking(BuildContext dialogContext) async {
    // Validate time selection (either regular slot or custom time)
    final hasTimeSelection =
        _useCustomTime ? _customTime != null : _selectedTimeSlot != null;

    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        !hasTimeSelection ||
        _selectedServiceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate console count for PS5/PS4
    if ((_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4') &&
        _consoleCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 console'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Check if slot is already booked (considering duration)
      final allBookings =
          await _firestore
              .collection('bookings')
              .where('date', isEqualTo: dateId)
              .where('serviceType', isEqualTo: _selectedServiceType)
              .get();

      // Parse selected time slot (convert from 12-hour to 24-hour format for comparison)
      // Handle both regular time slot and custom time
      String selectedTime24Hour;
      if (_useCustomTime && _customTime != null) {
        // Convert custom time to 24-hour format string
        final hour = _customTime!.hour.toString().padLeft(2, '0');
        final minute = _customTime!.minute.toString().padLeft(2, '0');
        selectedTime24Hour = '$hour:$minute';
      } else {
        selectedTime24Hour = _formatTime24Hour(_selectedTimeSlot!);
      }

      final selectedParts = selectedTime24Hour.split(':');
      final selectedHour =
          selectedParts.length == 2 ? int.tryParse(selectedParts[0]) ?? 0 : 0;
      final selectedMinute =
          selectedParts.length == 2 ? int.tryParse(selectedParts[1]) ?? 0 : 0;

      // Calculate duration based on service type
      double ourDurationHours;
      if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR') {
        ourDurationHours = _durationMinutes / 60.0; // Convert minutes to hours
      } else if (_selectedServiceType == 'Theatre') {
        ourDurationHours = _theatreHours.toDouble();
      } else {
        ourDurationHours = _durationHours.toDouble();
      }

      // Check if any existing booking overlaps with our selected time slot
      bool hasConflict = false;
      for (var doc in allBookings.docs) {
        final data = doc.data();
        final bookedTimeSlot = data['timeSlot'] as String? ?? '';
        final bookedDuration =
            (data['durationHours'] as num?)?.toDouble() ?? 1.0;
        final status =
            (data['status'] as String? ?? 'pending').toLowerCase().trim();

        // Skip if no time slot
        if (bookedTimeSlot.isEmpty) continue;

        // IMPORTANT: Check conflicts with 'pending', 'confirmed', and 'done' bookings
        // Only 'cancelled' bookings don't block (time slots are available)
        // Once a booking is made, it blocks the slot regardless of pending/done status
        if (status == 'cancelled') {
          continue; // Skip - don't check for conflicts, allow the booking
        }
        // 'pending', 'confirmed', and 'done' bookings will cause conflicts

        final bookedParts = bookedTimeSlot.split(':');
        final bookedHour =
            bookedParts.length == 2 ? int.tryParse(bookedParts[0]) ?? 0 : 0;
        final bookedMinute =
            bookedParts.length == 2 ? int.tryParse(bookedParts[1]) ?? 0 : 0;

        // Convert to decimal hours for accurate comparison
        final bookedStartDecimal = bookedHour + (bookedMinute / 60.0);
        final bookedEndDecimal = bookedStartDecimal + bookedDuration;

        // Convert our selected time to decimal hours
        final ourStartDecimal = selectedHour + (selectedMinute / 60.0);
        final ourEndDecimal = ourStartDecimal + ourDurationHours;

        // Check if our booking overlaps with existing booking
        if ((ourStartDecimal >= bookedStartDecimal &&
                ourStartDecimal < bookedEndDecimal) ||
            (ourEndDecimal > bookedStartDecimal &&
                ourEndDecimal <= bookedEndDecimal) ||
            (ourStartDecimal <= bookedStartDecimal &&
                ourEndDecimal >= bookedEndDecimal)) {
          hasConflict = true;
          break;
        }
      }

      if (hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This time slot conflicts with an existing booking',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check for conflicts with active sessions
      final hasActiveSessionConflict = await BookingLogicService.hasTimeConflict(
        deviceType: _selectedServiceType!,
        date: dateId,
        timeSlot: selectedTime24Hour,
        durationHours: ourDurationHours,
      );

      if (hasActiveSessionConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This time slot conflicts with an active session. Please check active sessions first.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Calculate duration based on service type
      double durationHours;
      if (_selectedServiceType == 'Simulator' || _selectedServiceType == 'VR') {
        durationHours = _durationMinutes / 60.0; // Convert minutes to hours
      } else if (_selectedServiceType == 'Theatre') {
        durationHours = _theatreHours.toDouble();
      } else {
        durationHours = _durationHours.toDouble();
      }

      // Convert selected time slot from 12-hour to 24-hour format for storage
      // Handle both regular time slot and custom time
      String timeSlot24Hour;
      if (_useCustomTime && _customTime != null) {
        // Convert custom time to 24-hour format string
        final hour = _customTime!.hour.toString().padLeft(2, '0');
        final minute = _customTime!.minute.toString().padLeft(2, '0');
        timeSlot24Hour = '$hour:$minute';
      } else {
        timeSlot24Hour = _formatTime24Hour(_selectedTimeSlot!);
      }

      final bookingData = {
        'serviceType': _selectedServiceType,
        'date': dateId,
        'dateTimestamp': Timestamp.fromDate(_selectedDate),
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
        'status': 'pending', // pending, confirmed, cancelled
      };

      await _firestore.collection('bookings').add(bookingData);

      if (mounted) {
        Navigator.pop(dialogContext);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Reset form
        _selectedServiceType = null;
        _selectedDate = DateTime.now();
        _selectedTimeSlot = null;
        _useCustomTime = false;
        _customTime = null;
        _nameController.clear();
        _phoneController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final maxDate = now.add(const Duration(days: 7));

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

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    // Clean the phone number - remove spaces, dashes, parentheses, and other non-digit characters
    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // Check if phone number is valid
    if (cleanedNumber.isEmpty ||
        cleanedNumber == 'NA' ||
        phoneNumber == 'N/A') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid phone number. Cannot make call.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Ensure phone number has at least 10 digits
    if (cleanedNumber.length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phone number is too short: $cleanedNumber'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Try launching directly - some devices don't properly report tel: support via canLaunchUrl
      // Use tel: format (standard format for phone numbers)
      Uri uri = Uri.parse('tel:$cleanedNumber');

      // Try to launch the phone dialer
      // Note: We don't check canLaunchUrl first because some devices incorrectly return false
      // for tel: URIs even though they can handle them
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched && mounted) {
          // If launchUrl returns false, try with platformDefault mode
          try {
            await launchUrl(uri, mode: LaunchMode.platformDefault);
          } catch (e2) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Could not open phone dialer for $cleanedNumber.\n'
                    'Please ensure your device has phone capability.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        }
      } catch (launchError) {
        // If external application mode fails, try platform default
        try {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        } catch (e2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Cannot make call to $cleanedNumber.\n'
                  'Error: ${e2.toString()}\n'
                  'Please ensure your device has a phone dialer app installed.',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making call: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _markAsDone(String bookingId) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Start Active Session'),
            content: const Text(
              'Are you sure you want to mark this booking as done?\n\n'
              'This will:\n'
              '• Create an active session for the customer\n'
              '• Add the booking services to the session\n'
              '• Remove the booking from the booking list\n\n'
              'The session will use the same pricing and calculation rules.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // Fetch booking data
      final bookingDoc = await _firestore.collection('bookings').doc(bookingId).get();
      
      if (!bookingDoc.exists) {
        throw Exception('Booking not found');
      }

      final bookingData = bookingDoc.data() as Map<String, dynamic>;
      
      // Validate booking data
      BookingToSessionConverter.validateBooking(bookingData);
      
      // Convert booking to active session using centralized logic
      final sessionId = await BookingToSessionConverter.convertBookingToActiveSession(
        bookingId: bookingId,
        bookingData: bookingData,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading indicator
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Booking converted to active session successfully!\n'
              'Session ID: ${sessionId.substring(0, 8)}...',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading indicator
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error converting booking to session: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _deleteBooking(
    String bookingId, {
    bool isHistory = false,
  }) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Booking'),
            content: Text(
              isHistory
                  ? 'Are you sure you want to delete this booking from history? This action cannot be undone.'
                  : 'Are you sure you want to delete this booking? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      // Delete from appropriate collection
      // Try the specified collection first, then fallback to the other if not found
      bool deleted = false;

      if (isHistory) {
        try {
          // Check if document exists in booking_history
          final doc =
              await _firestore
                  .collection('booking_history')
                  .doc(bookingId)
                  .get();
          if (doc.exists) {
            await _firestore
                .collection('booking_history')
                .doc(bookingId)
                .delete();
            deleted = true;
          } else {
            // Try bookings collection as fallback
            final bookingsDoc =
                await _firestore.collection('bookings').doc(bookingId).get();
            if (bookingsDoc.exists) {
              await _firestore.collection('bookings').doc(bookingId).delete();
              deleted = true;
            }
          }
        } catch (e) {
          debugPrint('Error deleting from booking_history: $e');
        }
      } else {
        try {
          // Check if document exists in bookings
          final doc =
              await _firestore.collection('bookings').doc(bookingId).get();
          if (doc.exists) {
            await _firestore.collection('bookings').doc(bookingId).delete();
            deleted = true;
          } else {
            // Try booking_history collection as fallback
            final historyDoc =
                await _firestore
                    .collection('booking_history')
                    .doc(bookingId)
                    .get();
            if (historyDoc.exists) {
              await _firestore
                  .collection('booking_history')
                  .doc(bookingId)
                  .delete();
              deleted = true;
            }
          }
        } catch (e) {
          debugPrint('Error deleting from bookings: $e');
        }
      }

      if (mounted) {
        if (deleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isHistory
                    ? 'Booking deleted from history successfully.'
                    : 'Booking deleted successfully. Time slot is now available.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Booking not found. It may have already been deleted.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Pending', icon: Icon(Icons.pending, size: 18)),
            Tab(text: 'Active Sessions', icon: Icon(Icons.play_circle, size: 18)),
            Tab(text: 'Completed', icon: Icon(Icons.history, size: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: Column(
        children: [
          // Selected Date Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.purple.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Colors.purple.shade700,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Selected Date: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
              ],
            ),
          ),
          // Tab View
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Pending Bookings Tab
                _buildPendingBookingsTab(dateId),
                // Active Sessions Tab
                _buildActiveSessionsTab(),
                // Completed Sessions Tab
                _buildCompletedSessionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingBookingsTab(String dateId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Type Buttons
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
            ),
            itemCount: _serviceTypes.length,
            itemBuilder: (context, index) {
              final serviceType = _serviceTypes[index];
              Color serviceColor;
              IconData serviceIcon;

              switch (serviceType) {
                case 'PS5':
                  serviceColor = Colors.blue;
                  serviceIcon = Icons.sports_esports;
                  break;
                case 'PS4':
                  serviceColor = Colors.purple.shade700;
                  serviceIcon = Icons.videogame_asset;
                  break;
                case 'VR':
                  serviceColor = Colors.purple.shade500;
                  serviceIcon = Icons.view_in_ar;
                  break;
                case 'Simulator':
                  serviceColor = Colors.orange.shade700;
                  serviceIcon = Icons.directions_car;
                  break;
                case 'Theatre':
                  serviceColor = Colors.red.shade700;
                  serviceIcon = Icons.movie;
                  break;
                default:
                  serviceColor = Colors.grey;
                  serviceIcon = Icons.category;
              }

              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: () => _checkAvailability(serviceType, _selectedDate),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [serviceColor, serviceColor.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(serviceIcon, size: 48, color: Colors.white),
                        const SizedBox(height: 12),
                        Text(
                          serviceType,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check Availability',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // Book Now Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to new booking creation page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateBookingPage(
                      selectedDate: _selectedDate,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text(
                'Book Now',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Today's Bookings
          Text(
            'Bookings for ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.purple.shade700,
            ),
          ),
          const SizedBox(height: 12),
          // Bookings List - Check history for past dates, active for today/future
          StreamBuilder<QuerySnapshot>(
            stream: _getPendingBookingsStream(dateId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No bookings for this date',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Sort bookings by time slot manually
              final sortedDocs = snapshot.data!.docs.toList();
              sortedDocs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final timeA = dataA['timeSlot'] as String? ?? '';
                final timeB = dataB['timeSlot'] as String? ?? '';
                return timeA.compareTo(timeB);
              });

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedDocs.length,
                itemBuilder: (context, index) {
                  final doc = sortedDocs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final serviceType = data['serviceType'] ?? 'Unknown';
                  final timeSlot24Hour = data['timeSlot'] ?? '';
                  final timeSlot = _formatTime12Hour(timeSlot24Hour);
                  final customerName = data['customerName'] ?? 'Unknown';
                  final phoneNumber = data['phoneNumber'] ?? 'N/A';
                  final durationHours = data['durationHours'] ?? 1;
                  final consoleCount = data['consoleCount'];
                  final totalPeople = data['totalPeople'];
                  final status = data['status'] ?? 'pending';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _getServiceColor(serviceType),
                            child: Icon(
                              _getServiceIcon(serviceType),
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '$serviceType',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeSlot,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            status == 'confirmed' ||
                                                    status == 'done'
                                                ? Colors.green.shade100
                                                : status == 'cancelled'
                                                ? Colors.red.shade100
                                                : Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              status == 'confirmed' ||
                                                      status == 'done'
                                                  ? Colors.green.shade700
                                                  : status == 'cancelled'
                                                  ? Colors.red.shade700
                                                  : Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  customerName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      '${durationHours}h',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    if (consoleCount != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$consoleCount consoles',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                    if (serviceType == 'Theatre' &&
                                        totalPeople != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$totalPeople people',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.phone, size: 20),
                                color: Colors.green.shade700,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed:
                                    phoneNumber != 'N/A' &&
                                            phoneNumber.isNotEmpty
                                        ? () => _makePhoneCall(phoneNumber)
                                        : null,
                                tooltip: 'Call $customerName',
                              ),
                              const SizedBox(height: 4),
                              if (status != 'done')
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    size: 20,
                                  ),
                                  color: Colors.purple.shade700,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _markAsDone(doc.id),
                                  tooltip: 'Mark as Done',
                                ),
                              const SizedBox(height: 4),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                color: Colors.red.shade700,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  // Determine if booking is from history (past date) or active
                                  final todayId = DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(DateTime.now());
                                  final bookingDate =
                                      data['date'] as String? ?? '';
                                  final isHistory =
                                      bookingDate.compareTo(todayId) < 0;
                                  _deleteBooking(doc.id, isHistory: isHistory);
                                },
                                tooltip: 'Delete Booking',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getServiceColor(String serviceType) {
    switch (serviceType) {
      case 'PS5':
        return Colors.blue;
      case 'PS4':
        return Colors.purple.shade700;
      case 'VR':
        return Colors.purple.shade500;
      case 'Simulator':
        return Colors.orange.shade700;
      case 'Theatre':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData _getServiceIcon(String serviceType) {
    switch (serviceType) {
      case 'PS5':
        return Icons.sports_esports;
      case 'PS4':
        return Icons.videogame_asset;
      case 'VR':
        return Icons.view_in_ar;
      case 'Simulator':
        return Icons.directions_car;
      case 'Theatre':
        return Icons.movie;
      default:
        return Icons.category;
    }
  }

  void _showServiceTypeSelectionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Select Service Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  _serviceTypes.map((serviceType) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getServiceColor(serviceType),
                        child: Icon(
                          _getServiceIcon(serviceType),
                          color: Colors.white,
                        ),
                      ),
                      title: Text(serviceType),
                      onTap: () {
                        Navigator.pop(context);
                        // Navigate to new booking creation page with selected service type
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateBookingPage(
                              selectedDate: _selectedDate,
                              serviceType: serviceType,
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  Widget _buildActiveSessionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('active_sessions')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Active Sessions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Active sessions will appear here when bookings are marked as Done',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          );
        }

        final sessions = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final doc = sessions[index];
            final sessionData = doc.data() as Map<String, dynamic>;
            final sessionId = doc.id;
            final customerName = sessionData['customerName'] as String? ?? 'Customer';
            final services = List<Map<String, dynamic>>.from(
              sessionData['services'] ?? [],
            );
            final totalAmount = (sessionData['totalAmount'] ?? 0).toDouble();
            final startTime = (sessionData['startTime'] as Timestamp?)?.toDate();

            // Get primary device type from first service or deviceType field
            String deviceType = sessionData['deviceType'] as String? ?? '';
            if (deviceType.isEmpty && services.isNotEmpty) {
              deviceType = services.first['type'] as String? ?? 'Unknown';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 3,
              child: InkWell(
                onTap: () async {
                  // Load session and navigate to detail page
                  await context.read<SessionProvider>().loadSession(sessionId);
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SessionDetailPage(),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _getServiceColor(deviceType),
                        child: Icon(
                          _getServiceIcon(deviceType),
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$deviceType • ${services.length} service${services.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (startTime != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Started: ${DateFormat('MMM dd, HH:mm').format(startTime)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Rs ${totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCompletedSessionsTab() {
    // Show "done" bookings from active collection and archived bookings from history
    return Column(
      children: [
        // Date Filter for History
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.purple.shade50,
          child: Row(
            children: [
              Icon(Icons.filter_list, color: Colors.purple.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                'Filter by Date:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final maxDate = now;
                    final minDate = now.subtract(const Duration(days: 365));

                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _historyFilterDate,
                      firstDate: minDate,
                      lastDate: maxDate,
                    );

                    if (picked != null) {
                      setState(() {
                        _historyFilterDate = picked;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Colors.purple.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat(
                              'MMM dd, yyyy',
                            ).format(_historyFilterDate),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.purple.shade700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 18,
                            color: Colors.purple.shade700,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _historyFilterDate =
                                  DateTime.now(); // Reset to current date
                            });
                          },
                          tooltip: 'Reset to Today',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // History List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                _firestore
                    .collection('bookings')
                    .where('status', isEqualTo: 'done')
                    .limit(100)
                    .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Also get archived bookings
              return FutureBuilder<QuerySnapshot>(
                future:
                    _firestore.collection('booking_history').limit(100).get(),
                builder: (context, archiveSnapshot) {
                  // Combine done bookings and archived bookings
                  // Track which collection each booking came from
                  List<Map<String, dynamic>> allBookings = [];

                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    for (var doc in snapshot.data!.docs) {
                      allBookings.add({
                        'doc': doc,
                        'isHistory': false, // From 'bookings' collection
                      });
                    }
                  }

                  if (archiveSnapshot.hasData &&
                      archiveSnapshot.data!.docs.isNotEmpty) {
                    for (var doc in archiveSnapshot.data!.docs) {
                      allBookings.add({
                        'doc': doc,
                        'isHistory': true, // From 'booking_history' collection
                      });
                    }
                  }

                  // Apply date filter
                  final filterDateId = DateFormat(
                    'yyyy-MM-dd',
                  ).format(_historyFilterDate);
                  allBookings =
                      allBookings.where((item) {
                        final doc = item['doc'] as QueryDocumentSnapshot;
                        final data = doc.data() as Map<String, dynamic>;
                        final bookingDate = data['date'] as String? ?? '';
                        return bookingDate == filterDateId;
                      }).toList();

                  if (allBookings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No completed bookings for ${DateFormat('MMM dd, yyyy').format(_historyFilterDate)}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Sort by date (archived date or booking date)
                  allBookings.sort((a, b) {
                    final docA = a['doc'] as QueryDocumentSnapshot;
                    final docB = b['doc'] as QueryDocumentSnapshot;
                    final dataA = docA.data() as Map<String, dynamic>;
                    final dataB = docB.data() as Map<String, dynamic>;

                    // Try archivedAt first, then dateTimestamp, then completedAt
                    DateTime dateA =
                        (dataA['archivedAt'] as Timestamp?)?.toDate() ??
                        (dataA['dateTimestamp'] as Timestamp?)?.toDate() ??
                        (dataA['completedAt'] as Timestamp?)?.toDate() ??
                        DateTime(2000);
                    DateTime dateB =
                        (dataB['archivedAt'] as Timestamp?)?.toDate() ??
                        (dataB['dateTimestamp'] as Timestamp?)?.toDate() ??
                        (dataB['completedAt'] as Timestamp?)?.toDate() ??
                        DateTime(2000);

                    return dateB.compareTo(dateA);
                  });

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: allBookings.length,
                    itemBuilder: (context, index) {
                      final item = allBookings[index];
                      final doc = item['doc'] as QueryDocumentSnapshot;
                      final isHistory = item['isHistory'] as bool;
                      final data = doc.data() as Map<String, dynamic>;
                      final serviceType = data['serviceType'] ?? 'Unknown';
                      final timeSlot24Hour = data['timeSlot'] ?? '';
                      final timeSlot = _formatTime12Hour(timeSlot24Hour);
                      final customerName = data['customerName'] ?? 'Unknown';
                      final phoneNumber = data['phoneNumber'] ?? 'N/A';
                      final durationHours = data['durationHours'] ?? 1;
                      final consoleCount = data['consoleCount'];
                      final totalPeople = data['totalPeople'];
                      final date =
                          (data['dateTimestamp'] as Timestamp?)?.toDate();
                      final completedAt =
                          (data['completedAt'] as Timestamp?)?.toDate();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _getServiceColor(serviceType),
                                child: Icon(
                                  _getServiceIcon(serviceType),
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '$serviceType',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          timeSlot,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        if (date != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            DateFormat('MMM dd').format(date),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      customerName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          '${durationHours}h',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        if (consoleCount != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '$consoleCount consoles',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                        if (serviceType == 'Theatre' &&
                                            totalPeople != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '$totalPeople people',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (completedAt != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Completed: ${DateFormat('MMM dd, hh:mm a').format(completedAt)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.phone, size: 20),
                                    color: Colors.green.shade700,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed:
                                        phoneNumber != 'N/A' &&
                                                phoneNumber.isNotEmpty
                                            ? () => _makePhoneCall(phoneNumber)
                                            : null,
                                    tooltip: 'Call $customerName',
                                  ),
                                  const SizedBox(height: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    color: Colors.red.shade700,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed:
                                        () => _deleteBooking(
                                          doc.id,
                                          isHistory: isHistory,
                                        ),
                                    tooltip: 'Delete from History',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
