import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/session_provider.dart';
import '../services/session_service.dart';
import '../services/device_capacity_service.dart';
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
  final SessionService _sessionService = SessionService();
  Map<int, Map<String, dynamic>?> _foundUserHistory = {}; // Store found history for each customer index
  Map<int, int> _mobileLengths = {}; // Track mobile number lengths for UI updates
  Map<int, bool> _searchCompleted = {}; // Track if search has completed for each index

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
  void initState() {
    super.initState();
    // Initialize mobile lengths and search status for the first customer
    _mobileLengths[0] = 0;
    _searchCompleted[0] = false;
  }

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
      final newIndex = _customerControllers.length;
      _customerControllers.add(TextEditingController());
      _mobileControllers.add(TextEditingController());
      _mobileLengths[newIndex] = 0;
      _searchCompleted[newIndex] = false;
    });
  }

  void _removeCustomer(int index) {
    if (_customerControllers.length > 1) {
      setState(() {
        _customerControllers[index].dispose();
        _mobileControllers[index].dispose();
        _customerControllers.removeAt(index);
        _mobileControllers.removeAt(index);
        _foundUserHistory.remove(index);
        _mobileLengths.remove(index);
        // Update indices for remaining items
        final newLengths = <int, int>{};
        for (int i = 0; i < _mobileControllers.length; i++) {
          if (_mobileLengths.containsKey(i + 1)) {
            newLengths[i] = _mobileLengths[i + 1]!;
          } else {
            newLengths[i] = _mobileControllers[i].text.length;
          }
        }
        _mobileLengths = newLengths;
      });
    }
  }

  /// Search for user history by phone number
  Future<void> _searchUserHistory(int index) async {
    final phoneNumber = _mobileControllers[index].text.trim();
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
    final currentHistory = _foundUserHistory[index];
    if (currentHistory != null) {
      final historyPhone = currentHistory['phoneNumber'] as String?;
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
        _foundUserHistory[index] = null; // Clear previous result
        _searchCompleted[index] = false; // Mark as searching
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
          duration: Duration(seconds: 10), // Increased timeout
        ),
      );
    }

    try {
      // Add timeout to prevent hanging
      final historyData = await _sessionService.searchUserHistoryByPhone(phoneNumber)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print('Search timeout for phone: $phoneNumber');
              return null;
            },
          );
      
      if (!mounted) return;
      
      // Update state immediately
      setState(() {
        _foundUserHistory[index] = historyData;
        _searchCompleted[index] = true; // Mark search as completed
        if (historyData != null && _customerControllers[index].text.trim().isEmpty) {
          // Auto-fill name if field is empty
          final customerName = historyData['customerName'] as String? ?? '';
          // Extract name if it contains phone number in format "Name (phone)"
          if (customerName.contains('(')) {
            _customerControllers[index].text = customerName.split('(')[0].trim();
          } else {
            _customerControllers[index].text = customerName;
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
          content: Text('Error searching history: ${e.toString().length > 50 ? e.toString().substring(0, 50) + "..." : e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _foundUserHistory[index] = null;
        _searchCompleted[index] = true; // Mark as completed even on error
      });
    }
  }

  /// Auto-fill customer data from history and create session
  Future<void> _autoFillFromHistory(int index) async {
    final historyData = _foundUserHistory[index];
    if (historyData == null) return;

    final phoneNumber = _mobileControllers[index].text.trim();
    if (phoneNumber.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate service type
    if (_selectedServiceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a service type first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get customer name
    String customerName = _customerControllers[index].text.trim();
    if (customerName.isEmpty) {
      customerName = historyData['customerName'] as String? ?? '';
      // Extract name if it contains phone number in format "Name (phone)"
      if (customerName.contains('(')) {
        customerName = customerName.split('(')[0].trim();
      }
      _customerControllers[index].text = customerName;
    }

    if (customerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find customer name in history'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check for booking conflicts
    try {
      await _checkBookingConflict();
    } catch (e) {
      // Error already shown in _checkBookingConflict
      return;
    }

    // Create session with phone number
    setState(() {
      _isCreating = true;
    });

    try {
      // Format customer data
      final customerNameWithPhone = '$customerName ($phoneNumber)';
      
      await context.read<SessionProvider>().createSession(
        customerNameWithPhone,
        phoneNumber: phoneNumber,
      );

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get default duration in hours based on service type
  double _getDefaultDuration(String serviceType) {
    switch (serviceType) {
      case 'PS5':
      case 'PS4':
        return 1.0; // Default 1 hour
      case 'Theatre':
        return 1.0; // Default 1 hour
      case 'Simulator':
      case 'VR':
        return 0.5; // Default 30 minutes (0.5 hours)
      default:
        return 1.0;
    }
  }

  Future<void> _checkBookingConflict({bool showError = true}) async {
    if (_selectedServiceType == null || _selectedServiceType!.isEmpty) {
      return; // No service type selected, skip check
    }

    try {
      final now = DateTime.now();
      final dateId = DateFormat('yyyy-MM-dd').format(now);
      final currentHour = now.hour;
      final currentMinute = now.minute;
      final currentTime24Hour =
          '${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}';

      // Get default duration for the selected service type
      final defaultDuration = _getDefaultDuration(_selectedServiceType!);

      final selectedServiceType = _selectedServiceType!.trim();

      // Check device capacity first
      final capacity = await DeviceCapacityService.getDeviceCapacity(selectedServiceType);
      
      if (capacity > 0) {
        // Use capacity-based checking: check if all slots are booked
        final canBook = await DeviceCapacityService.canMakeBooking(
          deviceType: selectedServiceType,
          date: dateId,
          timeSlot: currentTime24Hour,
          durationHours: defaultDuration,
        );

        if (!canBook) {
          // All slots are booked
          final availableSlots = await DeviceCapacityService.getAvailableSlots(
            deviceType: selectedServiceType,
            date: dateId,
            timeSlot: currentTime24Hour,
            durationHours: defaultDuration,
          );

          final currentTime12Hour = _formatTime12Hour(currentTime24Hour);
          final ourEndHour = (currentHour + defaultDuration).floor();
          final ourEndMinute = ((currentHour + (currentMinute / 60.0) + defaultDuration - ourEndHour) * 60).round();
          final ourEndTime24Hour =
              '${ourEndHour.toString().padLeft(2, '0')}:${ourEndMinute.toString().padLeft(2, '0')}';
          final ourEndTime12Hour = _formatTime12Hour(ourEndTime24Hour);

          final errorMessage =
              '⚠️ Cannot create session: All $capacity $selectedServiceType slots are fully booked at this time.\n\n'
              'Your session time: $currentTime12Hour - $ourEndTime12Hour (${defaultDuration.toStringAsFixed(1)}h)\n'
              'Available slots: $availableSlots of $capacity\n\n'
              'Please wait until a slot becomes available or choose a different service type.\n'
              'Note: Different service types (e.g., PS5 and Theatre) can be booked at the same time.';

          if (showError && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage, style: const TextStyle(fontSize: 14)),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
              ),
            );
          }

          throw Exception(errorMessage);
        }
      } else {
        // Capacity is 0 (unlimited) - use old overlap-based checking for backward compatibility
        final bookingsSnapshot =
            await FirebaseFirestore.instance
                .collection('bookings')
                .where('date', isEqualTo: dateId)
                .where('serviceType', isEqualTo: selectedServiceType)
                .get();

        // Check if current time slot is booked
        for (var doc in bookingsSnapshot.docs) {
          final data = doc.data();
          final bookedServiceType = (data['serviceType'] as String? ?? '').trim();

          // Double-check: Only process bookings for the same service type
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

          // Parse booked time slot (e.g., "14:00" or "14:30")
          final bookedParts = bookedTimeSlot.split(':');
          if (bookedParts.length != 2) continue;

          final bookedHour = int.tryParse(bookedParts[0]) ?? 0;
          final bookedMinute = int.tryParse(bookedParts[1]) ?? 0;

          // Convert to decimal hours for accurate comparison
          final bookedStartDecimal = bookedHour + (bookedMinute / 60.0);
          final bookedEndDecimal = bookedStartDecimal + bookedDuration;

          // Convert current time to decimal hours
          final currentStartDecimal = currentHour + (currentMinute / 60.0);
          final currentEndDecimal = currentStartDecimal + defaultDuration;

          // Check if our session time overlaps with booked time range
          if ((currentStartDecimal >= bookedStartDecimal && currentStartDecimal < bookedEndDecimal) ||
              (currentEndDecimal > bookedStartDecimal && currentEndDecimal <= bookedEndDecimal) ||
              (currentStartDecimal <= bookedStartDecimal && currentEndDecimal >= bookedEndDecimal)) {
            // Format booked end time in 12-hour format
            final bookedEndHour = (bookedStartDecimal + bookedDuration).floor();
            final bookedEndMinute =
                ((bookedStartDecimal + bookedDuration - bookedEndHour) * 60).round();
            final bookedEndTime24Hour =
                '${bookedEndHour.toString().padLeft(2, '0')}:${bookedEndMinute.toString().padLeft(2, '0')}';
            final bookedEndTime12Hour = _formatTime12Hour(bookedEndTime24Hour);

            // Format current time and booked time in 12-hour format
            final currentTime12Hour = _formatTime12Hour(currentTime24Hour);
            final bookedTime12Hour = _formatTime12Hour(bookedTimeSlot);

            // Calculate our end time
            final ourEndHour = (currentStartDecimal + defaultDuration).floor();
            final ourEndMinute = ((currentStartDecimal + defaultDuration - ourEndHour) * 60).round();
            final ourEndTime24Hour =
                '${ourEndHour.toString().padLeft(2, '0')}:${ourEndMinute.toString().padLeft(2, '0')}';
            final ourEndTime12Hour = _formatTime12Hour(ourEndTime24Hour);

            final errorMessage =
                '⚠️ Cannot create session: This time slot is already booked for $selectedServiceType.\n\n'
                'Your session time: $currentTime12Hour - $ourEndTime12Hour (${defaultDuration.toStringAsFixed(1)}h)\n'
                'Existing booking: $bookedServiceType at $bookedTime12Hour - $bookedEndTime12Hour (${bookedDuration.toStringAsFixed(1)}h)\n\n'
                'Please wait until the booking ends or choose a different service type.\n'
                'Note: Different service types (e.g., PS5 and Theatre) can be booked at the same time.';

            if (showError && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMessage, style: const TextStyle(fontSize: 14)),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
                ),
              );
            }

            throw Exception(errorMessage);
          }
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
              children:
                  _serviceTypes.map((type) {
                    final isSelected = _selectedServiceType == type;
                    return ChoiceChip(
                      label: Text(type),
                      selected: isSelected,
                      onSelected: (selected) async {
                        setState(() {
                          _selectedServiceType = selected ? type : null;
                        });

                        // Check for booking conflicts immediately when service type is selected
                        if (selected && type.isNotEmpty) {
                          try {
                            await _checkBookingConflict(showError: true);
                          } catch (e) {
                            // Error already shown in _checkBookingConflict
                            // Deselect the service type to prevent session creation
                            if (mounted) {
                              setState(() {
                                _selectedServiceType = null;
                              });
                            }
                          }
                        }
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
                            maxLength: 10,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Mobile Number',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.phone),
                              suffixIcon: (_mobileLengths[index] ?? 0) == 10
                                  ? IconButton(
                                      icon: const Icon(Icons.search),
                                      onPressed: () => _searchUserHistory(index),
                                      tooltip: 'Search user history',
                                    )
                                  : null,
                              counterText: '',
                              helperText: _foundUserHistory[index] != null
                                  ? '✓ User found in history!'
                                  : (_searchCompleted[index] == true && _foundUserHistory[index] == null)
                                      ? 'No user found'
                                      : (_mobileLengths[index] ?? 0) == 10
                                          ? 'Searching...'
                                          : 'Enter 10 digit mobile number',
                              helperMaxLines: 2,
                              helperStyle: TextStyle(
                                color: (_searchCompleted[index] == true && _foundUserHistory[index] == null)
                                    ? Colors.red
                                    : _foundUserHistory[index] != null
                                        ? Colors.green
                                        : null,
                              ),
                              errorText:
                                  (_mobileLengths[index] ?? 0) > 0 &&
                                          (_mobileLengths[index] ?? 0) != 10
                                      ? 'Mobile number must be 10 digits'
                                      : null,
                            ),
                            onChanged: (value) {
                              // Update length immediately
                              setState(() {
                                _mobileLengths[index] = value.length;
                                
                                // Clear found history and search status when number changes
                                if (_foundUserHistory[index] != null || _searchCompleted[index] == true) {
                                  _foundUserHistory[index] = null;
                                  _searchCompleted[index] = false;
                                }
                              });
                              
                              // Auto-search when 10 digits are entered
                              if (value.length == 10) {
                                // Small delay to ensure UI updates first
                                Future.delayed(const Duration(milliseconds: 300), () {
                                  if (mounted && _mobileControllers[index].text.length == 10) {
                                    _searchUserHistory(index);
                                  }
                                });
                              }
                            },
                          ),
                          if (_foundUserHistory[index] != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'User found in history',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Name: ${_foundUserHistory[index]!['customerName'] ?? 'Unknown'}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  ElevatedButton.icon(
                                    onPressed: () => _autoFillFromHistory(index),
                                    icon: const Icon(Icons.auto_fix_high, size: 16),
                                    label: const Text('Auto-fill & Create Session'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

                                if (mobile.isNotEmpty && mobile.length != 10) {
                                  hasError = true;
                                  errorMessage =
                                      'Mobile number for customer ${i + 1} must be 10 digits';
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

                              // Use first customer's phone number for the session
                              final primaryPhoneNumber = validCustomers.isNotEmpty 
                                  ? validCustomers.first['mobile'] 
                                  : null;

                              await context.read<SessionProvider>().createSession(
                                customerName,
                                phoneNumber: primaryPhoneNumber,
                              );

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

                                if (errorStr.contains('already booked') ||
                                    errorStr.contains('Cannot create session')) {
                                  // Extract the detailed conflict message (handles multi-line)
                                  final match = RegExp(
                                    r'Cannot create session: (.+)',
                                    dotAll: true,
                                  ).firstMatch(errorStr);
                                  if (match != null) {
                                    errorMessage =
                                        '⚠️ Booking Conflict\n\n${match.group(1)!.trim()}';
                                  } else {
                                    errorMessage =
                                        '⚠️ This time slot is already booked. Please wait or choose a different service type.';
                                  }
                                } else {
                                  errorMessage =
                                      'Error creating session:\n${errorStr.replaceAll('Exception: ', '').trim()}';
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      errorMessage,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 5),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
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
