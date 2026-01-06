import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/session_provider.dart';
import 'session_detail_page.dart';

class CreateSessionPage extends StatefulWidget {
  const CreateSessionPage({super.key});

  @override
  State<CreateSessionPage> createState() => _CreateSessionPageState();
}

class _CreateSessionPageState extends State<CreateSessionPage> {
  final List<TextEditingController> _customerControllers = [TextEditingController()];
  final List<TextEditingController> _mobileControllers = [TextEditingController()];
  bool _isCreating = false;
  String? _selectedServiceType;

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
  
  final List<String> _serviceTypes = ['PS5', 'PS4', 'VR', 'Simulator', 'Theatre'];

  @override
  void dispose() {
    for (var controller in _customerControllers) {
      controller.dispose();
    }
    for (var controller in _mobileControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addCustomer() {
    setState(() {
      _customerControllers.add(TextEditingController());
      _mobileControllers.add(TextEditingController());
    });
  }

  void _removeCustomer(int index) {
    if (_customerControllers.length > 1) {
      setState(() {
        _customerControllers[index].dispose();
        _mobileControllers[index].dispose();
        _customerControllers.removeAt(index);
        _mobileControllers.removeAt(index);
      });
    }
  }

  Future<void> _checkBookingConflict() async {
    if (_selectedServiceType == null || _selectedServiceType!.isEmpty) {
      return; // No service type selected, skip check
    }

    try {
      final now = DateTime.now();
      final dateId = DateFormat('yyyy-MM-dd').format(now);
      final currentHour = now.hour;
      final currentTimeSlot = '${currentHour.toString().padLeft(2, '0')}:00';

      // IMPORTANT: Only check bookings for the SAME service type
      // Different service types (e.g., PS5 vs Theatre) don't conflict
      final selectedServiceType = _selectedServiceType!.trim();
      final bookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('date', isEqualTo: dateId)
          .where('serviceType', isEqualTo: selectedServiceType)
          .get();

      // Check if current time slot is booked
      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final bookedServiceType = (data['serviceType'] as String? ?? '').trim();
        
        // Double-check: Only process bookings for the same service type
        // This is a safeguard in case the query doesn't filter correctly
        if (bookedServiceType.toLowerCase() != selectedServiceType.toLowerCase()) {
          continue; // Skip bookings for different service types
        }
        
        final status = (data['status'] as String? ?? 'pending').toLowerCase().trim();
        
        // Only check conflicts with 'pending', 'confirmed', and 'done' bookings
        // 'cancelled' bookings don't block
        if (status == 'cancelled') continue;

        final bookedTimeSlot = data['timeSlot'] as String? ?? '';
        if (bookedTimeSlot.isEmpty) continue;

        final bookedDuration = (data['durationHours'] as num?)?.toDouble() ?? 1.0;
        
        // Parse booked time slot (e.g., "14:00")
        final bookedParts = bookedTimeSlot.split(':');
        if (bookedParts.length != 2) continue;
        
        final bookedHour = int.tryParse(bookedParts[0]) ?? 0;
        final bookedStartDecimal = bookedHour.toDouble();
        final bookedEndDecimal = bookedStartDecimal + bookedDuration;

        // Check if current time falls within booked time range
        final currentDecimal = currentHour.toDouble();
        if (currentDecimal >= bookedStartDecimal && currentDecimal < bookedEndDecimal) {
          // Format booked end time in 12-hour format
          final bookedEndHour = (bookedStartDecimal + bookedDuration).floor();
          final bookedEndMinute = ((bookedStartDecimal + bookedDuration - bookedEndHour) * 60).round();
          final bookedEndTime24Hour = '${bookedEndHour.toString().padLeft(2, '0')}:${bookedEndMinute.toString().padLeft(2, '0')}';
          final bookedEndTime12Hour = _formatTime12Hour(bookedEndTime24Hour);
          
          // Format current time and booked time in 12-hour format
          final currentTime12Hour = _formatTime12Hour('$currentTimeSlot:00');
          final bookedTime12Hour = _formatTime12Hour(bookedTimeSlot);
          
          throw Exception(
            'Cannot create session: This time slot is already booked for $selectedServiceType.\n\n'
            'Current time: $currentTime12Hour\n'
            'Existing booking: $bookedServiceType at $bookedTime12Hour - $bookedEndTime12Hour (${bookedDuration.toStringAsFixed(1)}h)\n\n'
            'Please wait until the booking ends or choose a different service type.\n'
            'Note: Different service types (e.g., PS5 and Theatre) can be booked at the same time.'
          );
        }
      }
    } catch (e) {
      // Re-throw to let the caller handle it
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Session')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Service Type:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _serviceTypes.map((type) {
                final isSelected = _selectedServiceType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedServiceType = selected ? type : null;
                    });
                  },
                  selectedColor: Colors.blue.shade300,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Customer Details (Add multiple if needed):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _customerControllers.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Customer ${index + 1}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const Spacer(),
                              if (_customerControllers.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                  onPressed: () => _removeCustomer(index),
                                  tooltip: 'Remove customer',
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _customerControllers[index],
                            decoration: const InputDecoration(
                              labelText: 'Customer Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _mobileControllers[index],
                            keyboardType: TextInputType.phone,
                            maxLength: 9,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Mobile Number',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.phone),
                              prefixText: '+94 ',
                              counterText: '',
                              helperText: 'Enter 9 digit mobile number (without leading 0)',
                              helperMaxLines: 1,
                              errorText:
                                  _mobileControllers[index].text.isNotEmpty &&
                                          _mobileControllers[index].text.length != 9
                                      ? 'Mobile number must be 9 digits (without leading 0)'
                                      : null,
                            ),
                            onChanged: (value) {
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _addCustomer,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Customer'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed:
                      _isCreating
                          ? null
                          : () async {
                            // Prevent double-tapping
                            if (_isCreating) return;

                            setState(() {
                              _isCreating = true;
                            });

                            try {
                              // Validate service type selection
                              if (_selectedServiceType == null) {
                                if (mounted) {
                                  setState(() {
                                    _isCreating = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please select a service type'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // Check for booking conflicts at current time
                              await _checkBookingConflict();

                              // Validate all fields
                              bool hasError = false;
                              String errorMessage = '';

                              for (int i = 0; i < _customerControllers.length; i++) {
                                final name = _customerControllers[i].text.trim();
                                final mobile = _mobileControllers[i].text.trim();

                                if (name.isEmpty && mobile.isNotEmpty) {
                                  hasError = true;
                                  errorMessage = 'Please enter customer name for customer ${i + 1}';
                                  break;
                                }

                                if (name.isNotEmpty && mobile.isEmpty) {
                                  hasError = true;
                                  errorMessage = 'Please enter mobile number for customer ${i + 1}';
                                  break;
                                }

                                if (mobile.isNotEmpty && mobile.length != 9) {
                                  hasError = true;
                                  errorMessage =
                                      'Mobile number for customer ${i + 1} must be 9 digits (without leading 0)';
                                  break;
                                }
                              }

                              if (hasError) {
                                if (mounted) {
                                  setState(() {
                                    _isCreating = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(errorMessage),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // Get valid customers (both name and mobile filled)
                              final validCustomers = <Map<String, String>>[];
                              for (int i = 0; i < _customerControllers.length; i++) {
                                final name = _customerControllers[i].text.trim();
                                final mobile = _mobileControllers[i].text.trim();

                                if (name.isNotEmpty && mobile.isNotEmpty) {
                                  validCustomers.add({'name': name, 'mobile': mobile});
                                }
                              }

                              if (validCustomers.isEmpty) {
                                if (mounted) {
                                  setState(() {
                                    _isCreating = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter at least one customer with name and mobile number',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // Format customer data
                              final customerName = validCustomers
                                  .map((c) => '${c['name']} (${c['mobile']})')
                                  .join(', ');

                              await context.read<SessionProvider>().createSession(customerName);

                              if (mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SessionDetailPage()),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _isCreating = false;
                                });
                                
                                // Extract error message
                                String errorMessage = 'Error creating session';
                                final errorStr = e.toString();
                                
                                if (errorStr.contains('already booked') || errorStr.contains('Cannot create session')) {
                                  // Extract the detailed conflict message (handles multi-line)
                                  final match = RegExp(r'Cannot create session: (.+)', dotAll: true).firstMatch(errorStr);
                                  if (match != null) {
                                    errorMessage = '⚠️ Booking Conflict\n\n${match.group(1)!.trim()}';
                                  } else {
                                    errorMessage = '⚠️ This time slot is already booked. Please wait or choose a different service type.';
                                  }
                                } else {
                                  errorMessage = 'Error creating session:\n${errorStr.replaceAll('Exception: ', '').trim()}';
                                }
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      errorMessage,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 5),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    action: SnackBarAction(
                                      label: 'OK',
                                      textColor: Colors.white,
                                      onPressed: () {},
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                  child:
                      _isCreating
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                          : const Text('Start Session'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
