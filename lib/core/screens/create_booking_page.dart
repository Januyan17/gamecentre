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

  const CreateBookingPage({
    super.key,
    required this.selectedDate,
    this.serviceType,
  });

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

  final List<String> _serviceTypes = ['PS5', 'PS4', 'VR', 'Simulator', 'Theatre'];

  @override
  void initState() {
    super.initState();
    _selectedServiceType = widget.serviceType ?? 'PS5';
    _calculatePrice();
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
        const SnackBar(
          content: Text('Please enter customer name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedTimeSlot == null && !_useCustomTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a time slot'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_useCustomTime && _customTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a custom time'),
          backgroundColor: Colors.red,
        ),
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
              content: Text(
                'This time slot conflicts with an existing booking or active session',
              ),
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
          SnackBar(
            content: Text('Error creating booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Booking'),
      ),
      body: Column(
        children: [
          // Quick Access: Active Sessions
          _QuickAccessSection(),

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
                BoxShadow(
                  color: Colors.grey.shade300,
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            const Text(
              'Service Type',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _serviceTypes.map((type) {
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
                    setState(() {
                      _selectedServiceType = type;
                      _calculatePrice();
                    });
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            Text(
              '$_minutes',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
            const Text(
              'Time Slot',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _timeSlots.map((slot) {
                  final isSelected = _selectedTimeSlot == slot;
                  return FilterChip(
                    selected: isSelected,
                    label: Text(slot),
                    onSelected: (selected) {
                      setState(() {
                        _selectedTimeSlot = selected ? slot : null;
                      });
                    },
                  );
                }).toList(),
              ),
            ] else ...[
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Select Time'),
                subtitle: Text(
                  _customTime != null
                      ? _customTime!.format(context)
                      : 'Tap to select',
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
            if ((_selectedServiceType == 'PS4' || _selectedServiceType == 'PS5') && _consoleCount > 1) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Price per console:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
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
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
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
  const _QuickAccessSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('active_sessions')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Group sessions by device type
        final Map<String, List<Map<String, dynamic>>> sessionsByDevice = {};

        for (var doc in snapshot.data!.docs) {
          final sessionData = doc.data() as Map<String, dynamic>;
          final services = List<Map<String, dynamic>>.from(
            sessionData['services'] ?? [],
          );

          for (var service in services) {
            final deviceType = service['type'] as String? ?? '';
            if (deviceType.isEmpty) continue;

            if (!sessionsByDevice.containsKey(deviceType)) {
              sessionsByDevice[deviceType] = [];
            }

            sessionsByDevice[deviceType]!.add({
              'sessionId': doc.id,
              'sessionData': sessionData,
              'service': service,
            });
          }
        }

        if (sessionsByDevice.isEmpty) {
          return const SizedBox.shrink();
        }

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
                  child: _QuickAccessCard(
                    deviceType: deviceType,
                    sessions: sessions,
                  ),
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

  const _QuickAccessCard({
    required this.deviceType,
    required this.sessions,
  });

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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SessionDetailPage(),
              ),
            );
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeRemaining,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

