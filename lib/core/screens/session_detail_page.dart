import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/session_provider.dart';
import '../services/price_calculator.dart';
import 'device_selection_page.dart';
import 'add_service_page.dart';

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionProvider>().refreshSession();
    });
  }

  void _editService(int index, Map<String, dynamic> service) {
    if (service['type'] == 'PS4' || service['type'] == 'PS5') {
      // Edit PS4/PS5 with time calculator
      showDialog(
        context: context,
        builder: (context) => _EditDeviceDialog(
          device: service,
          onConfirm: (updatedService) async {
            await context.read<SessionProvider>().updateService(index, updatedService);
            if (mounted) Navigator.pop(context);
          },
        ),
      );
    } else {
      // For other services, show a simple edit dialog
      _showEditDialog(index, service);
    }
  }

  void _showEditDialog(int index, Map<String, dynamic> service) {
    // Simple edit for non-PS4/PS5 services
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${service['type']}'),
        content: const Text('Editing for this service type is not available. Please delete and add again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _deleteService(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service'),
        content: const Text('Are you sure you want to delete this service?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<SessionProvider>().deleteService(index);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Session'),
        actions: [
          StreamBuilder(
            stream: provider.sessionsRef().doc(provider.activeSessionId).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final customerName = data?['customerName'] ?? 'Unknown';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(child: Text(customerName)),
                );
              }
              return const SizedBox();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Total amount card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                const Text(
                  'Total Amount',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                StreamBuilder<DocumentSnapshot>(
                  stream: provider.activeSessionId != null
                      ? provider.sessionsRef().doc(provider.activeSessionId).snapshots()
                      : null,
                  builder: (context, snapshot) {
                    double total = provider.currentTotal;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      total = (data?['totalAmount'] ?? 0).toDouble();
                    }
                    return Text(
                      'Rs ${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                    );
                  },
                ),
              ],
            ),
          ),

          // Services list - Use StreamBuilder for real-time updates
          Expanded(
            child: provider.activeSessionId == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          'No active session',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<DocumentSnapshot>(
                    stream: provider.sessionsRef().doc(provider.activeSessionId).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 64, color: Colors.red),
                              SizedBox(height: 16),
                              Text(
                                'Session not found',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      final services = List<Map<String, dynamic>>.from(data['services'] ?? []);
                      final currentTotal = (data['totalAmount'] ?? 0).toDouble();

                      // Update provider state
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (provider.activeSessionId != null) {
                          provider.currentTotal = currentTotal;
                          provider.services = services;
                        }
                      });

                      if (services.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sports_esports, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No services added yet',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: () => provider.refreshSession(),
                        child: ListView.builder(
                          itemCount: services.length,
                          itemBuilder: (context, index) {
                        final service = services[index];
                        final type = service['type'] ?? 'Unknown';
                        final price = (service['price'] ?? 0).toDouble();
                        final multiplayer = service['multiplayer'] ?? false;
                        
                        String subtitle = 'Rs ${price.toStringAsFixed(2)}';
                        if (service['hours'] != null && service['minutes'] != null) {
                          subtitle = '${service['hours']}h ${service['minutes']}m${multiplayer ? ' (Multiplayer)' : ''} - Rs ${price.toStringAsFixed(2)}';
                        } else if (service['duration'] != null) {
                          subtitle = '${service['duration']} min - Rs ${price.toStringAsFixed(2)}';
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: type == 'PS5' ? Colors.blue : Colors.purple,
                              child: Text(
                                type == 'PS5' ? 'PS5' : type == 'PS4' ? 'PS4' : type[0],
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text('$type${multiplayer ? ' (Multiplayer)' : ''}'),
                            subtitle: Text(subtitle),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _editService(index, service),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteService(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                        ),
                      );
                    },
                  ),
          ),

          // Action buttons
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
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DeviceSelectionPage()),
                      ).then((_) => provider.refreshSession());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Device'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddServicePage()),
                      ).then((_) => provider.refreshSession());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Other Services'),
                  ),
                ),
              ],
            ),
          ),
          
          // Close session button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('End Session'),
                    content: Text(
                      'Total Amount: Rs ${provider.currentTotal.toStringAsFixed(2)}\n\nAre you sure you want to end this session? This will add it to history.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('End Session'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  await provider.closeSession();
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Session ended and added to history')),
                    );
                  }
                }
              },
              child: const Text(
                'END SESSION',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditDeviceDialog extends StatefulWidget {
  final Map<String, dynamic> device;
  final Function(Map<String, dynamic>) onConfirm;

  const _EditDeviceDialog({
    required this.device,
    required this.onConfirm,
  });

  @override
  State<_EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  late int hours;
  late int minutes;
  late bool multiplayer;
  double price = 0;

  @override
  void initState() {
    super.initState();
    hours = widget.device['hours'] ?? 0;
    minutes = widget.device['minutes'] ?? 0;
    multiplayer = widget.device['multiplayer'] ?? false;
    _calculatePrice();
  }

  void _calculatePrice() {
    if (widget.device['type'] == 'PS4') {
      price = PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        multiplayer: multiplayer,
      );
    } else if (widget.device['type'] == 'PS5') {
      price = PriceCalculator.ps5Price(
        hours: hours,
        minutes: minutes,
        multiplayer: multiplayer,
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.device['type']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text('Hours'),
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
                      Text('$hours', style: const TextStyle(fontSize: 24)),
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
                  const Text('Minutes'),
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
                      Text('$minutes', style: const TextStyle(fontSize: 24)),
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
                Text('Total Time: ${hours}h ${minutes}m'),
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (hours == 0 && minutes == 0)
              ? null
              : () {
                  widget.onConfirm({
                    ...widget.device,
                    'hours': hours,
                    'minutes': minutes,
                    'price': price,
                    'multiplayer': multiplayer,
                  });
                },
          child: const Text('Update'),
        ),
      ],
    );
  }
}

