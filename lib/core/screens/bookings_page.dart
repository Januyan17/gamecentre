import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedServiceType;
  DateTime _selectedDate = DateTime.now();
  String? _selectedTimeSlot;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  int _consoleCount = 1; // For PS5/PS4
  int _theatreHours = 1; // For Theatre
  int _theatrePeople = 1; // For Theatre
  int _durationHours = 1; // Duration in hours for all services
  late TabController _tabController;

  final List<String> _serviceTypes = ['PS5', 'PS4', 'VR', 'Simulator', 'Theatre'];

  // Time slots (every hour from 9 AM to 11 PM)
  final List<String> _timeSlots = List.generate(15, (index) {
    final hour = 9 + index;
    return '${hour.toString().padLeft(2, '0')}:00';
  });

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability(String serviceType, DateTime date) async {
    setState(() {
      _selectedServiceType = serviceType;
      _selectedDate = date;
    });

    try {
      final dateId = DateFormat('yyyy-MM-dd').format(date);
      final bookingsSnapshot =
          await _firestore
              .collection('bookings')
              .where('date', isEqualTo: dateId)
              .where('serviceType', isEqualTo: serviceType)
              .get();

      // Show availability dialog
      if (mounted) {
        _showAvailabilityDialog(serviceType, date, bookingsSnapshot.docs);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error checking availability: $e')));
      }
    }
  }

  void _showAvailabilityDialog(
    String serviceType,
    DateTime date,
    List<QueryDocumentSnapshot> bookings,
  ) {
    // Calculate all booked slots considering duration
    final Set<String> bookedSlots = {};
    for (var doc in bookings) {
      final data = doc.data() as Map<String, dynamic>;
      final timeSlot = data['timeSlot'] as String? ?? '';
      final durationHours = (data['durationHours'] as num?)?.toInt() ?? 1;

      if (timeSlot.isNotEmpty) {
        // Parse time slot (e.g., "14:00")
        final parts = timeSlot.split(':');
        if (parts.length == 2) {
          final startHour = int.tryParse(parts[0]) ?? 0;
          // Mark all slots within the duration as booked
          for (int i = 0; i < durationHours; i++) {
            final hour = startHour + i;
            if (hour <= 23) {
              final slot = '${hour.toString().padLeft(2, '0')}:00';
              bookedSlots.add(slot);
            }
          }
        }
      }
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('$serviceType Availability - ${DateFormat('MMM dd, yyyy').format(date)}'),
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
                            final isBooked = bookedSlots.contains(slot);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isBooked ? Colors.red.shade50 : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isBooked ? Colors.red.shade300 : Colors.green.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isBooked ? Icons.close : Icons.check,
                                    size: 14,
                                    color: isBooked ? Colors.red : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    slot,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: isBooked ? Colors.red.shade700 : Colors.green.shade700,
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
    );
  }

  void _showBookingDialog(String serviceType, DateTime date) {
    _selectedServiceType = serviceType;
    _selectedDate = date;
    _selectedTimeSlot = null;
    _nameController.clear();
    _phoneController.clear();
    _consoleCount = 1;
    _theatreHours = 1;
    _theatrePeople = 1;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => Dialog(
                  insetPadding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
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
                          // Date Display
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, color: Colors.purple.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM dd, yyyy').format(date),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Time Slot Selection
                          Text(
                            'Select Time Slot:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                _timeSlots.map((slot) {
                                  final isSelected = _selectedTimeSlot == slot;
                                  return ChoiceChip(
                                    label: Text(slot),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setDialogState(() {
                                        _selectedTimeSlot = selected ? slot : null;
                                      });
                                    },
                                    selectedColor: Colors.purple.shade300,
                                    labelStyle: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                }).toList(),
                          ),
                          const SizedBox(height: 20),
                          // Customer Name
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Customer Name *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Phone Number
                          TextField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          // Duration Selection (for all services)
                          Text(
                            'Duration (Hours):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                          // Service-specific fields
                          if (serviceType == 'PS5' || serviceType == 'PS4') ...[
                            Text(
                              'Number of Consoles:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                          ] else if (serviceType == 'Theatre') ...[
                            Text(
                              'Hours:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                onPressed: () => _createBooking(context),
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
          ),
    );
  }

  Future<void> _createBooking(BuildContext dialogContext) async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _selectedTimeSlot == null ||
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
    if ((_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4') && _consoleCount < 1) {
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

      // Parse selected time slot
      final selectedParts = _selectedTimeSlot!.split(':');
      final selectedHour = selectedParts.length == 2 ? int.tryParse(selectedParts[0]) ?? 0 : 0;

      // Check if any existing booking overlaps with our selected time slot
      bool hasConflict = false;
      for (var doc in allBookings.docs) {
        final data = doc.data();
        final bookedTimeSlot = data['timeSlot'] as String? ?? '';
        final bookedDuration = (data['durationHours'] as num?)?.toInt() ?? 1;

        if (bookedTimeSlot.isNotEmpty) {
          final bookedParts = bookedTimeSlot.split(':');
          final bookedHour = bookedParts.length == 2 ? int.tryParse(bookedParts[0]) ?? 0 : 0;
          final bookedEndHour = bookedHour + bookedDuration;

          // Check if our booking overlaps with existing booking
          final ourEndHour = selectedHour + _durationHours;
          if ((selectedHour >= bookedHour && selectedHour < bookedEndHour) ||
              (ourEndHour > bookedHour && ourEndHour <= bookedEndHour) ||
              (selectedHour <= bookedHour && ourEndHour >= bookedEndHour)) {
            hasConflict = true;
            break;
          }
        }
      }

      if (hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time slot conflicts with an existing booking'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final bookingData = {
        'serviceType': _selectedServiceType,
        'date': dateId,
        'dateTimestamp': Timestamp.fromDate(_selectedDate),
        'timeSlot': _selectedTimeSlot,
        'durationHours': _durationHours,
        'customerName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        if (_selectedServiceType == 'PS5' || _selectedServiceType == 'PS4')
          'consoleCount': _consoleCount,
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
        _nameController.clear();
        _phoneController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating booking: $e'), backgroundColor: Colors.red),
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
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot make call to $phoneNumber'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _markAsDone(String bookingId) async {
    try {
      await _firestore.collection('bookings').doc(bookingId).update({
        'status': 'done',
        'completedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking marked as done'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating booking: $e'), backgroundColor: Colors.red),
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
            Tab(text: 'Active Bookings', icon: Icon(Icons.event, size: 18)),
            Tab(text: 'History', icon: Icon(Icons.history, size: 18)),
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
                Icon(Icons.calendar_today, color: Colors.purple.shade700, size: 18),
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
                // Active Bookings Tab
                _buildActiveBookingsTab(dateId),
                // History Tab
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBookingsTab(String dateId) {
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
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
                // Show service type selection dialog
                _showServiceTypeSelectionDialog();
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          // Bookings List (Active only - not done)
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('bookings').where('date', isEqualTo: dateId).snapshots(),
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
                      Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'No bookings for this date',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
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
                  final timeSlot = data['timeSlot'] ?? '';
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            status == 'confirmed'
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
                                              status == 'confirmed'
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
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      '${durationHours}h',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    if (consoleCount != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$consoleCount consoles',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    ],
                                    if (serviceType == 'Theatre' && totalPeople != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$totalPeople people',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                                onPressed: () => _makePhoneCall(phoneNumber),
                                tooltip: 'Call $customerName',
                              ),
                              const SizedBox(height: 4),
                              if (status != 'done')
                                IconButton(
                                  icon: const Icon(Icons.check_circle, size: 20),
                                  color: Colors.purple.shade700,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _markAsDone(doc.id),
                                  tooltip: 'Mark as Done',
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
                        child: Icon(_getServiceIcon(serviceType), color: Colors.white),
                      ),
                      title: Text(serviceType),
                      onTap: () {
                        Navigator.pop(context);
                        _showBookingDialog(serviceType, _selectedDate);
                      },
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ],
          ),
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
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

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No completed bookings',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
              ],
            ),
          );
        }

        // Sort by completed date
        final sortedDocs = snapshot.data!.docs.toList();
        sortedDocs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final dateA = (dataA['completedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final dateB = (dataB['completedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return dateB.compareTo(dateA);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sortedDocs.length,
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final serviceType = data['serviceType'] ?? 'Unknown';
            final timeSlot = data['timeSlot'] ?? '';
            final customerName = data['customerName'] ?? 'Unknown';
            final phoneNumber = data['phoneNumber'] ?? 'N/A';
            final durationHours = data['durationHours'] ?? 1;
            final consoleCount = data['consoleCount'];
            final totalPeople = data['totalPeople'];
            final date = (data['dateTimestamp'] as Timestamp?)?.toDate();
            final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _getServiceColor(serviceType),
                      child: Icon(_getServiceIcon(serviceType), color: Colors.white, size: 16),
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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeSlot,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                              if (date != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM dd').format(date),
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            customerName,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${durationHours}h',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                              if (consoleCount != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '$consoleCount consoles',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                              if (serviceType == 'Theatre' && totalPeople != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '$totalPeople people',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                    IconButton(
                      icon: const Icon(Icons.phone, size: 20),
                      color: Colors.green.shade700,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _makePhoneCall(phoneNumber),
                      tooltip: 'Call $customerName',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
