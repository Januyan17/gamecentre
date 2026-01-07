import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/session_provider.dart';
import '../services/price_calculator.dart';
import '../services/session_service.dart';
import 'session_detail_page.dart';

class DeviceSelectionPage extends StatefulWidget {
  const DeviceSelectionPage({super.key});

  @override
  State<DeviceSelectionPage> createState() => _DeviceSelectionPageState();
}

class _DeviceSelectionPageState extends State<DeviceSelectionPage> {
  final List<Map<String, dynamic>> selectedDevices = [];

  // Helper method to get scenarios stream with error handling
  Stream<QuerySnapshot> _getCommonScenariosStream() {
    try {
      return FirebaseFirestore.instance
          .collection('common_scenarios')
          .orderBy('order', descending: false)
          .snapshots();
    } catch (e) {
      // If order index doesn't exist, return stream without orderBy
      debugPrint('Order index not found, using stream without order: $e');
      return FirebaseFirestore.instance
          .collection('common_scenarios')
          .snapshots();
    }
  }

  void _addDevice(String type) {
    showDialog(
      context: context,
      builder:
          (context) => _TimeCalculatorDialog(
            deviceType: type,
            onConfirm: (hours, minutes, price, additionalControllers) {
              setState(() {
                selectedDevices.add({
                  'id': const Uuid().v4(),
                  'type': type,
                  'hours': hours,
                  'minutes': minutes,
                  'price': price,
                  'additionalControllers': additionalControllers,
                  'startTime': DateTime.now().toIso8601String(),
                });
              });
              Navigator.pop(context);
            },
          ),
    );
  }

  void _quickAdd(
    String type,
    int count,
    int hours,
    int minutes,
    int additionalControllers,
  ) async {
    // Calculate price for one device
    double singlePrice = 0.0;
    if (type == 'PS4') {
      singlePrice = await PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    } else if (type == 'PS5') {
      singlePrice = await PriceCalculator.ps5Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    }

    setState(() {
      for (int i = 0; i < count; i++) {
        selectedDevices.add({
          'id': const Uuid().v4(),
          'type': type,
          'hours': hours,
          'minutes': minutes,
          'price': singlePrice,
          'additionalControllers': additionalControllers,
          'startTime': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
  }

  void _editDevice(int index) {
    final device = selectedDevices[index];
    showDialog(
      context: context,
      builder:
          (context) => _TimeCalculatorDialog(
            deviceType: device['type'],
            initialHours: device['hours'],
            initialMinutes: device['minutes'],
            initialAdditionalControllers: device['additionalControllers'] ?? 0,
            onConfirm: (hours, minutes, price, additionalControllers) {
              setState(() {
                selectedDevices[index] = {
                  ...device,
                  'hours': hours,
                  'minutes': minutes,
                  'price': price,
                  'additionalControllers': additionalControllers,
                };
              });
              Navigator.pop(context);
            },
          ),
    );
  }

  void _removeDevice(int index) {
    setState(() {
      selectedDevices.removeAt(index);
    });
  }

  void _saveDevices() async {
    if (selectedDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one device')),
      );
      return;
    }

    final provider = context.read<SessionProvider>();

    // Check if there's an active session
    if (provider.activeSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active session. Please create a session first.'),
          backgroundColor: Colors.red,
        ),
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
      // Add all services sequentially
      for (var device in selectedDevices) {
        await provider.addService(device);
      }

      // Wait a bit to ensure Firestore has updated and synced
      await Future.delayed(const Duration(milliseconds: 800));

      // Refresh the session to ensure we have the latest data
      await provider.refreshSession();

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pop(
          context,
        ); // Go back to previous page (SessionDetailPage or Dashboard)

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedDevices.length} device(s) added successfully',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading

        // Extract error message
        String errorMessage = 'Error adding devices';
        final errorStr = e.toString();

        if (errorStr.contains('conflicts with an existing booking')) {
          // Extract the detailed conflict message (handles multi-line)
          final match = RegExp(
            r'This time slot conflicts with an existing booking\.\s*(.+)',
            dotAll: true,
          ).firstMatch(errorStr);
          if (match != null) {
            errorMessage = '⚠️ Booking Conflict\n\n${match.group(1)!.trim()}';
          } else {
            errorMessage =
                '⚠️ This time slot conflicts with an existing booking.\nPlease choose a different time.';
          }
        } else if (errorStr.contains('No active session')) {
          errorMessage = 'No active session. Please create a session first.';
        } else {
          errorMessage =
              'Error adding devices:\n${errorStr.replaceAll('Exception: ', '').trim()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage, style: const TextStyle(fontSize: 14)),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Devices'),
        actions: [
          if (selectedDevices.isNotEmpty)
            TextButton(
              onPressed: _saveDevices,
              child: const Text(
                'Add Selected',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Quick Add Section - Common Scenarios from Admin
          StreamBuilder<QuerySnapshot>(
            stream: _getCommonScenariosStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.blue.shade50,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                debugPrint('Error loading common scenarios: ${snapshot.error}');
                return const SizedBox.shrink();
              }

              List<Map<String, dynamic>> scenarios = [];
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                final docs = snapshot.data!.docs.toList();
                // Sort manually if orderBy failed
                try {
                  docs.sort((a, b) {
                    final orderA =
                        (a.data() as Map<String, dynamic>)['order'] as int? ??
                        0;
                    final orderB =
                        (b.data() as Map<String, dynamic>)['order'] as int? ??
                        0;
                    return orderA.compareTo(orderB);
                  });
                } catch (e) {
                  debugPrint('Error sorting scenarios: $e');
                }

                scenarios =
                    docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return {
                        'id': doc.id,
                        'type': data['type'] ?? 'PS5',
                        'count': data['count'] ?? 1,
                        'hours': data['hours'] ?? 1,
                        'minutes': data['minutes'] ?? 0,
                        'additionalControllers':
                            data['additionalControllers'] ?? 0,
                        'label': data['label'] ?? '',
                      };
                    }).toList();
              }

              if (scenarios.isEmpty) {
                return const SizedBox.shrink();
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
                        Icon(
                          Icons.flash_on,
                          size: 18,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Quick Add',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          scenarios.map((scenario) {
                            final type = scenario['type'] as String? ?? 'PS5';
                            final count =
                                (scenario['count'] as num?)?.toInt() ?? 1;
                            final hours =
                                (scenario['hours'] as num?)?.toInt() ?? 1;
                            final minutes =
                                (scenario['minutes'] as num?)?.toInt() ?? 0;
                            final additionalControllers =
                                (scenario['additionalControllers'] as num?)
                                    ?.toInt() ??
                                0;
                            final label =
                                scenario['label'] as String? ??
                                '$count $type${hours > 0 ? ' ${hours}h' : ''}${additionalControllers > 0 ? ' Multi' : ''}';
                            final color =
                                type == 'PS5' ? Colors.blue : Colors.purple;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    () => _quickAdd(
                                      type,
                                      count,
                                      hours,
                                      minutes,
                                      additionalControllers,
                                    ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
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
                                        additionalControllers > 0
                                            ? Icons.people
                                            : Icons.sports_esports,
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
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // Quick Access: Active Sessions
          const Divider(),

          // Device selection buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _addDevice('PS4'),
                        icon: const Icon(Icons.sports_esports),
                        label: const Text('Add PS4'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _addDevice('PS5'),
                        icon: const Icon(Icons.sports_esports),
                        label: const Text('Add PS5'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(),

          // Selected devices list
          Expanded(
            child:
                selectedDevices.isEmpty
                    ? const Center(
                      child: Text(
                        'No devices selected\nTap "Add PS4" or "Add PS5" to start',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      itemCount: selectedDevices.length,
                      itemBuilder: (context, index) {
                        final device = selectedDevices[index];
                        final hours = device['hours'] as int;
                        final minutes = device['minutes'] as int;
                        final price = device['price'] as double;
                        final additionalControllers =
                            device['additionalControllers'] as int? ?? 0;

                        // Format time display
                        String timeDisplay = '';
                        if (hours > 0 && minutes > 0) {
                          timeDisplay = '${hours}h ${minutes}m';
                        } else if (hours > 0) {
                          timeDisplay = '${hours}h';
                        } else if (minutes > 0) {
                          timeDisplay = '${minutes}m';
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  device['type'] == 'PS5'
                                      ? Colors.blue
                                      : Colors.purple,
                              child: Text(
                                device['type'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              '${device['type']} Console',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: $timeDisplay',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                if (additionalControllers > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Multiplayer: +$additionalControllers Controller${additionalControllers > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Price: Rs ${price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _editDevice(index),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removeDevice(index),
                                  tooltip: 'Remove',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),

          // Total summary and Add button
          if (selectedDevices.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  // Total row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Rs ${selectedDevices.fold<double>(0, (sum, device) => sum + (device['price'] as double)).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Add button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveDevices,
                      icon: const Icon(Icons.check_circle, size: 24),
                      label: Text(
                        'Add ${selectedDevices.length} Device${selectedDevices.length != 1 ? 's' : ''} to Session',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeCalculatorDialog extends StatefulWidget {
  final String deviceType;
  final int? initialHours;
  final int? initialMinutes;
  final int? initialAdditionalControllers;
  final Function(
    int hours,
    int minutes,
    double price,
    int additionalControllers,
  )
  onConfirm;

  const _TimeCalculatorDialog({
    required this.deviceType,
    this.initialHours,
    this.initialMinutes,
    this.initialAdditionalControllers,
    required this.onConfirm,
  });

  @override
  State<_TimeCalculatorDialog> createState() => _TimeCalculatorDialogState();
}

class _TimeCalculatorDialogState extends State<_TimeCalculatorDialog> {
  late int hours;
  late int minutes;
  late int additionalControllers;
  bool enableAdditionalControllers = false;
  double price = 0;
  double controllerPrice = 150; // Default, will be fetched from database
  double deviceHourlyRate = 0; // PS4 or PS5 base rate
  double psChargesForHours = 0; // PS charges for full hours
  double controllerChargesForHours = 0; // Controller charges for full hours
  double additionalMinutesPrice = 0; // Price for additional minutes

  @override
  void initState() {
    super.initState();
    hours = widget.initialHours ?? 0;
    minutes = widget.initialMinutes ?? 0;
    additionalControllers = widget.initialAdditionalControllers ?? 0;
    // Enable additional controllers if initial value is greater than 0
    enableAdditionalControllers =
        (widget.initialAdditionalControllers ?? 0) > 0;
    _fetchControllerPrice();
    _calculatePrice();
  }

  void _fetchControllerPrice() async {
    // Fetch dynamic controller price from database
    controllerPrice = await PriceCalculator.getAdditionalControllerPrice();
    setState(() {});
  }

  void _calculatePrice() async {
    // Get device hourly rate from Firestore
    double ps4Rate = 250.0;
    double ps5Rate = 350.0;
    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('settings').doc('pricing').get();
      if (doc.exists) {
        final prices = doc.data() as Map<String, dynamic>;
        ps4Rate = (prices['ps4HourlyRate'] ?? 250.0).toDouble();
        ps5Rate = (prices['ps5HourlyRate'] ?? 350.0).toDouble();
      }
    } catch (e) {
      // Use defaults
    }

    if (widget.deviceType == 'PS4') {
      deviceHourlyRate = ps4Rate;
    } else if (widget.deviceType == 'PS5') {
      deviceHourlyRate = ps5Rate;
    }

    // Calculate breakdown
    psChargesForHours = (hours * deviceHourlyRate).toDouble();
    controllerChargesForHours =
        (hours * additionalControllers * controllerPrice).toDouble();

    // Calculate additional minutes
    double baseHourlyRate =
        deviceHourlyRate + (additionalControllers * controllerPrice);
    additionalMinutesPrice = 0.0;
    if (minutes > 0) {
      additionalMinutesPrice = (baseHourlyRate / 2) * (minutes / 30.0);
    }

    // Calculate total price
    if (widget.deviceType == 'PS4') {
      price = await PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    } else if (widget.deviceType == 'PS5') {
      price = await PriceCalculator.ps5Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.deviceType} - Time Calculator'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    const Text('Hours', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (hours > 0) {
                              setState(() {
                                hours--;
                                _calculatePrice();
                              });
                            }
                          },
                        ),
                        Text(
                          '$hours',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            setState(() {
                              hours++;
                              _calculatePrice();
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Minutes', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (minutes > 0) {
                              setState(() {
                                minutes -= 15;
                                if (minutes < 0) minutes = 0;
                                _calculatePrice();
                              });
                            }
                          },
                        ),
                        Text(
                          '$minutes',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            setState(() {
                              minutes += 15;
                              if (minutes >= 60) {
                                hours += minutes ~/ 60;
                                minutes = minutes % 60;
                              }
                              _calculatePrice();
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Additional Controllers Toggle and Selection
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Toggle Switch Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Additional Controllers',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: enableAdditionalControllers,
                        onChanged: (value) {
                          setState(() {
                            enableAdditionalControllers = value;
                            if (!value) {
                              // Reset to 0 when disabled
                              additionalControllers = 0;
                            }
                            _calculatePrice();
                          });
                        },
                      ),
                    ],
                  ),
                  // Controller Selection (only shown when enabled)
                  if (enableAdditionalControllers) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Rs ${controllerPrice.toStringAsFixed(0)} per controller per hour',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (hours > 0 && additionalControllers > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Controller charges for ${hours}h: Rs ${(hours * additionalControllers * controllerPrice).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (additionalControllers > 0) {
                              setState(() {
                                additionalControllers--;
                                _calculatePrice();
                              });
                            }
                          },
                        ),
                        Container(
                          width: 60,
                          alignment: Alignment.center,
                          child: Text(
                            '$additionalControllers',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            setState(() {
                              additionalControllers++;
                              _calculatePrice();
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total Time
                  Text(
                    'Total Time: ${hours}h ${minutes}m',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Detailed Breakdown
                  const Text(
                    'Price Breakdown:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  // PS Charges
                  if (hours > 0) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            '${widget.deviceType} charges (${hours}h × Rs ${deviceHourlyRate.toStringAsFixed(0)}):',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rs ${psChargesForHours.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  // Controller Charges
                  if (additionalControllers > 0 && hours > 0) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            'Controller charges (${additionalControllers} × Rs ${controllerPrice.toStringAsFixed(0)} × ${hours}h):',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rs ${controllerChargesForHours.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  // Additional Minutes
                  if (minutes > 0) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            'Additional ${minutes}m (50% of hourly rate):',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rs ${additionalMinutesPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  const Divider(height: 16),
                  // Total Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Price:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Rs ${price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: Additional minutes are charged at half the hourly rate',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              (hours == 0 && minutes == 0)
                  ? null
                  : () {
                    widget.onConfirm(
                      hours,
                      minutes,
                      price,
                      additionalControllers,
                    );
                  },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Centralized utility class for converting bookings to active sessions.
/// All common logic for booking → active session transition, price calculations,
/// validation, and session duration handling is centralized here.
class BookingToSessionConverter {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final SessionService _sessionService = SessionService();
  static const Uuid _uuid = Uuid();

  /// Converts a booking to an active session.
  ///
  /// This method:
  /// 1. Creates a new active session with the customer name
  /// 2. Converts booking data to service format
  /// 3. Calculates prices using PriceCalculator (same logic as device_selection_page)
  /// 4. Adds services to the session
  /// 5. Removes the booking from the bookings collection
  ///
  /// Throws an exception if conversion fails.
  static Future<String> convertBookingToActiveSession({
    required String bookingId,
    required Map<String, dynamic> bookingData,
  }) async {
    try {
      // Extract booking information
      final serviceType = bookingData['serviceType'] as String? ?? '';
      final customerName = bookingData['customerName'] as String? ?? 'Customer';
      final phoneNumber = bookingData['phoneNumber'] as String?;
      final date = bookingData['date'] as String? ?? '';
      final timeSlot = bookingData['timeSlot'] as String? ?? '';

      if (serviceType.isEmpty) {
        throw Exception('Service type is required');
      }
      if (customerName.isEmpty) {
        throw Exception('Customer name is required');
      }
      if (timeSlot.isEmpty) {
        throw Exception('Time slot is required');
      }

      // Parse time slot to create startTime
      final startTime = _parseTimeSlotToDateTime(date, timeSlot);

      // Create active session with booking reference
      final sessionId = await _sessionService.createSession(
        customerName,
        phoneNumber: phoneNumber,
      );

      // Store booking reference and device info in session
      await _firestore.collection('active_sessions').doc(sessionId).update({
        'bookingId': bookingId,
        'bookingDate': date,
        'bookingTimeSlot': timeSlot,
        'deviceType': serviceType, // Store primary device type for quick access
      });

      // Convert booking to service(s) based on service type
      final services = await _convertBookingToServices(
        bookingData: bookingData,
        startTime: startTime,
      );

      // Add all services to the session
      for (var service in services) {
        await _sessionService.addService(sessionId, service);
      }

      // Save booking to history before deleting
      final historyData = <String, dynamic>{
        ...bookingData,
        'status': 'converted_to_session',
        'convertedAt': FieldValue.serverTimestamp(),
        'sessionId': sessionId,
        'originalBookingId': bookingId,
      };

      // Add to booking_history collection
      await _firestore
          .collection('booking_history')
          .doc(bookingId)
          .set(historyData);

      // Remove booking from bookings collection
      await _firestore.collection('bookings').doc(bookingId).delete();

      return sessionId;
    } catch (e) {
      throw Exception(
        'Failed to convert booking to active session: ${e.toString()}',
      );
    }
  }

  /// Converts booking data to service format(s).
  /// Handles all service types: PS4, PS5, VR, Simulator, Theatre.
  /// Uses the same price calculation logic as device_selection_page.
  static Future<List<Map<String, dynamic>>> _convertBookingToServices({
    required Map<String, dynamic> bookingData,
    required DateTime startTime,
  }) async {
    final serviceType = bookingData['serviceType'] as String? ?? '';
    final services = <Map<String, dynamic>>[];

    switch (serviceType) {
      case 'PS4':
      case 'PS5':
        services.addAll(
          await _convertConsoleBooking(
            bookingData: bookingData,
            startTime: startTime,
            deviceType: serviceType,
          ),
        );
        break;

      case 'VR':
        services.add(
          await _convertVrBooking(
            bookingData: bookingData,
            startTime: startTime,
          ),
        );
        break;

      case 'Simulator':
        services.add(
          await _convertSimulatorBooking(
            bookingData: bookingData,
            startTime: startTime,
          ),
        );
        break;

      case 'Theatre':
        services.add(
          await _convertTheatreBooking(
            bookingData: bookingData,
            startTime: startTime,
          ),
        );
        break;

      default:
        throw Exception('Unsupported service type: $serviceType');
    }

    return services;
  }

  /// Converts PS4/PS5 booking to service(s).
  /// Handles multiple consoles (consoleCount).
  /// Uses PriceCalculator.ps4Price() or ps5Price() for price calculation.
  static Future<List<Map<String, dynamic>>> _convertConsoleBooking({
    required Map<String, dynamic> bookingData,
    required DateTime startTime,
    required String deviceType,
  }) async {
    final durationHours =
        (bookingData['durationHours'] as num?)?.toDouble() ?? 1.0;
    final consoleCount = (bookingData['consoleCount'] as num?)?.toInt() ?? 1;

    // Extract hours and minutes from duration
    final hours = durationHours.floor();
    final minutes = ((durationHours - hours) * 60).round();

    // For now, we assume no additional controllers from booking
    // This can be extended if bookings include controller information
    final additionalControllers = 0;

    // Calculate price using the same logic as device_selection_page
    double price;
    if (deviceType == 'PS4') {
      price = await PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    } else {
      price = await PriceCalculator.ps5Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    }

    // Create one service per console
    final services = <Map<String, dynamic>>[];
    for (int i = 0; i < consoleCount; i++) {
      services.add({
        'id': _uuid.v4(),
        'type': deviceType,
        'hours': hours,
        'minutes': minutes,
        'price': price,
        'additionalControllers': additionalControllers,
        'startTime': startTime.toIso8601String(),
      });
    }

    return services;
  }

  /// Converts VR booking to service.
  /// Uses PriceCalculator.vr() for price calculation.
  static Future<Map<String, dynamic>> _convertVrBooking({
    required Map<String, dynamic> bookingData,
    required DateTime startTime,
  }) async {
    final durationMinutes =
        (bookingData['durationMinutes'] as num?)?.toInt() ?? 30;

    // Calculate games: 5 minutes per game
    final games = (durationMinutes / 5).ceil();

    // Calculate slots: 2 games per slot
    final slots = (games / 2).ceil();

    // Calculate price: VR price per slot
    final pricePerSlot = await PriceCalculator.vr();
    final price = pricePerSlot * slots;

    return {
      'id': _uuid.v4(),
      'type': 'VR',
      'slots': slots,
      'games': games,
      'price': price,
      'startTime': startTime.toIso8601String(),
    };
  }

  /// Converts Simulator booking to service.
  /// Uses PriceCalculator.carSimulator() for price calculation.
  static Future<Map<String, dynamic>> _convertSimulatorBooking({
    required Map<String, dynamic> bookingData,
    required DateTime startTime,
  }) async {
    final durationMinutes =
        (bookingData['durationMinutes'] as num?)?.toInt() ?? 30;

    // Calculate games: 5 minutes per game
    final games = (durationMinutes / 5).ceil();

    // Calculate price: Simulator price per game
    final pricePerGame = await PriceCalculator.carSimulator();
    final price = pricePerGame * games;

    return {
      'id': _uuid.v4(),
      'type': 'Simulator',
      'games': games,
      'price': price,
      'startTime': startTime.toIso8601String(),
    };
  }

  /// Converts Theatre booking to service.
  /// Uses PriceCalculator.theatre() for price calculation.
  static Future<Map<String, dynamic>> _convertTheatreBooking({
    required Map<String, dynamic> bookingData,
    required DateTime startTime,
  }) async {
    final hours = (bookingData['hours'] as num?)?.toInt() ?? 1;
    final people = (bookingData['totalPeople'] as num?)?.toInt() ?? 1;

    // Calculate price using the same logic as device_selection_page
    final price = await PriceCalculator.theatre(hours: hours, people: people);

    return {
      'id': _uuid.v4(),
      'type': 'Theatre',
      'hours': hours,
      'people': people,
      'price': price,
      'startTime': startTime.toIso8601String(),
    };
  }

  /// Parses date and timeSlot strings to a DateTime object.
  static DateTime _parseTimeSlotToDateTime(String date, String timeSlot) {
    try {
      // Parse date (format: yyyy-MM-dd)
      final dateParts = date.split('-');
      if (dateParts.length != 3) {
        throw Exception('Invalid date format: $date');
      }

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      // Parse timeSlot (format: HH:mm)
      final timeParts = timeSlot.split(':');
      if (timeParts.length < 2) {
        throw Exception('Invalid time slot format: $timeSlot');
      }

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      // If parsing fails, use current time as fallback
      debugPrint(
        'Warning: Failed to parse booking time, using current time: $e',
      );
      return DateTime.now();
    }
  }

  /// Validates booking data before conversion.
  /// Returns true if booking is valid, throws exception otherwise.
  static void validateBooking(Map<String, dynamic> bookingData) {
    final serviceType = bookingData['serviceType'] as String? ?? '';
    if (serviceType.isEmpty) {
      throw Exception('Service type is required');
    }

    final customerName = bookingData['customerName'] as String? ?? '';
    if (customerName.isEmpty) {
      throw Exception('Customer name is required');
    }

    final timeSlot = bookingData['timeSlot'] as String? ?? '';
    if (timeSlot.isEmpty) {
      throw Exception('Time slot is required');
    }

    // Validate service-specific fields
    switch (serviceType) {
      case 'PS4':
      case 'PS5':
        final durationHours =
            (bookingData['durationHours'] as num?)?.toDouble();
        if (durationHours == null || durationHours <= 0) {
          throw Exception('Duration hours must be greater than 0');
        }
        break;

      case 'VR':
      case 'Simulator':
        final durationMinutes =
            (bookingData['durationMinutes'] as num?)?.toInt();
        if (durationMinutes == null || durationMinutes <= 0) {
          throw Exception('Duration minutes must be greater than 0');
        }
        break;

      case 'Theatre':
        final hours = (bookingData['hours'] as num?)?.toInt();
        if (hours == null || hours <= 0) {
          throw Exception('Theatre hours must be greater than 0');
        }
        final people = (bookingData['totalPeople'] as num?)?.toInt();
        if (people == null || people <= 0) {
          throw Exception('Number of people must be greater than 0');
        }
        break;
    }
  }
}
