import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/session_provider.dart';
import '../services/price_calculator.dart';

class DeviceSelectionPage extends StatefulWidget {
  const DeviceSelectionPage({super.key});

  @override
  State<DeviceSelectionPage> createState() => _DeviceSelectionPageState();
}

class _DeviceSelectionPageState extends State<DeviceSelectionPage> {
  final List<Map<String, dynamic>> selectedDevices = [];

  void _addDevice(String type) {
    showDialog(
      context: context,
      builder:
          (context) => _TimeCalculatorDialog(
            deviceType: type,
            onConfirm: (hours, minutes, price, multiplayer) {
              setState(() {
                selectedDevices.add({
                  'id': const Uuid().v4(),
                  'type': type,
                  'hours': hours,
                  'minutes': minutes,
                  'price': price,
                  'multiplayer': multiplayer,
                  'startTime': DateTime.now().toIso8601String(),
                });
              });
              Navigator.pop(context);
            },
          ),
    );
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
            initialMultiplayer: device['multiplayer'] ?? false,
            onConfirm: (hours, minutes, price, multiplayer) {
              setState(() {
                selectedDevices[index] = {
                  ...device,
                  'hours': hours,
                  'minutes': minutes,
                  'price': price,
                  'multiplayer': multiplayer,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select at least one device')));
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
        Navigator.pop(context); // Go back to previous page (SessionDetailPage or Dashboard)
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selectedDevices.length} device(s) added successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding devices: ${e.toString()}'),
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
        title: const Text('Select Devices'),
        actions: [
          if (selectedDevices.isNotEmpty)
            TextButton(
              onPressed: _saveDevices,
              child: const Text('Add Selected', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Device selection buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _addDevice('PS4'),
                  icon: const Icon(Icons.sports_esports),
                  label: const Text('Add PS4'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _addDevice('PS5'),
                  icon: const Icon(Icons.sports_esports),
                  label: const Text('Add PS5'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
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
                        final multiplayer = device['multiplayer'] ?? false;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(child: Text(device['type'])),
                            title: Text(
                              '${device['type']}${multiplayer ? ' (Multiplayer)' : ''} - ${hours}h ${minutes}m',
                            ),
                            subtitle: Text('Rs ${price.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _editDevice(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _removeDevice(index),
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
                      const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
  final bool? initialMultiplayer;
  final Function(int hours, int minutes, double price, bool multiplayer) onConfirm;

  const _TimeCalculatorDialog({
    required this.deviceType,
    this.initialHours,
    this.initialMinutes,
    this.initialMultiplayer,
    required this.onConfirm,
  });

  @override
  State<_TimeCalculatorDialog> createState() => _TimeCalculatorDialogState();
}

class _TimeCalculatorDialogState extends State<_TimeCalculatorDialog> {
  late int hours;
  late int minutes;
  late bool multiplayer;
  double price = 0;

  @override
  void initState() {
    super.initState();
    hours = widget.initialHours ?? 0;
    minutes = widget.initialMinutes ?? 0;
    multiplayer = widget.initialMultiplayer ?? false;
    _calculatePrice();
  }

  void _calculatePrice() {
    if (widget.deviceType == 'PS4') {
      price = PriceCalculator.ps4Price(hours: hours, minutes: minutes, multiplayer: multiplayer);
    } else if (widget.deviceType == 'PS5') {
      price = PriceCalculator.ps5Price(hours: hours, minutes: minutes, multiplayer: multiplayer);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.deviceType} - Time Calculator'),
      content: Column(
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
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
          // Multiplayer toggle
          SwitchListTile(
            title: const Text('Multiplayer (+Rs 150)'),
            subtitle: const Text('Add extra console for multiplayer'),
            value: multiplayer,
            onChanged: (value) {
              setState(() {
                multiplayer = value;
                _calculatePrice();
              });
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text('Total Time: ${hours}h ${minutes}m', style: const TextStyle(fontSize: 16)),
                if (multiplayer)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Multiplayer: +Rs 150',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Price: Rs ${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Note: Time is rounded up to nearest 15 minutes',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed:
              (hours == 0 && minutes == 0)
                  ? null
                  : () {
                    widget.onConfirm(hours, minutes, price, multiplayer);
                  },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
