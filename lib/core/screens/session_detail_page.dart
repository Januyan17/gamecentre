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
        builder:
            (context) => _EditDeviceDialog(
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
      builder:
          (context) => AlertDialog(
            title: Text('Edit ${service['type']}'),
            content: const Text(
              'Editing for this service type is not available. Please delete and add again.',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
    );
  }

  void _deleteService(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Service'),
            content: const Text('Are you sure you want to delete this service?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

  void _showDiscountDialog(
    BuildContext context,
    SessionProvider provider,
    double currentTotal,
    double currentDiscount,
  ) {
    final discountController = TextEditingController(
      text: currentDiscount > 0 ? currentDiscount.toStringAsFixed(2) : '',
    );
    bool isPercentage = false;

    showDialog(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Apply Discount'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Original Total: Rs ${currentTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: discountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: isPercentage ? 'Discount %' : 'Discount Amount (Rs)',
                            border: const OutlineInputBorder(),
                            prefixIcon: Icon(isPercentage ? Icons.percent : Icons.currency_rupee),
                          ),
                          onChanged: (value) {
                            setState(() {}); // Update preview
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Fixed Amount'),
                                selected: !isPercentage,
                                onSelected: (selected) {
                                  setState(() {
                                    isPercentage = false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('Percentage'),
                                selected: isPercentage,
                                onSelected: (selected) {
                                  setState(() {
                                    isPercentage = true;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (discountController.text.isNotEmpty)
                          Builder(
                            builder: (context) {
                              double discountValue = 0.0;
                              try {
                                final input = double.tryParse(discountController.text) ?? 0.0;
                                if (isPercentage) {
                                  discountValue = (currentTotal * input / 100).clamp(
                                    0.0,
                                    currentTotal,
                                  );
                                } else {
                                  discountValue = input.clamp(0.0, currentTotal);
                                }
                              } catch (e) {
                                discountValue = 0.0;
                              }

                              final finalAmount = (currentTotal - discountValue).clamp(
                                0.0,
                                double.infinity,
                              );

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Discount:'),
                                        Text(
                                          'Rs ${discountValue.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Final Amount:',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'Rs ${finalAmount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    if (currentDiscount > 0)
                      TextButton(
                        onPressed: () async {
                          await provider.removeDiscount();
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Discount removed'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'Remove Discount',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final discountText = discountController.text.trim();
                        if (discountText.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter discount amount'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final input = double.tryParse(discountText);
                        if (input == null || input <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a valid discount amount'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        double discountAmount = 0.0;
                        if (isPercentage) {
                          discountAmount = (currentTotal * input / 100).clamp(0.0, currentTotal);
                        } else {
                          discountAmount = input.clamp(0.0, currentTotal);
                        }

                        if (discountAmount > currentTotal) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Discount cannot be more than total amount'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        await provider.applyDiscount(discountAmount);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Discount of Rs ${discountAmount.toStringAsFixed(2)} applied',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
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
            child: StreamBuilder<DocumentSnapshot>(
              stream:
                  provider.activeSessionId != null
                      ? provider.sessionsRef().doc(provider.activeSessionId).snapshots()
                      : null,
              builder: (context, snapshot) {
                double total = provider.currentTotal;
                double discount = 0.0;
                double finalAmount = total;

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  total = (data?['totalAmount'] ?? 0).toDouble();
                  discount = (data?['discount'] ?? 0).toDouble();
                  finalAmount = (data?['finalAmount'] ?? total);
                }

                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        IconButton(
                          icon: Icon(
                            discount > 0 ? Icons.discount : Icons.local_offer_outlined,
                            color: discount > 0 ? Colors.green : Colors.blue,
                          ),
                          onPressed: () => _showDiscountDialog(context, provider, total, discount),
                          tooltip: discount > 0 ? 'Edit Discount' : 'Apply Discount',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rs ${total.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        decoration: discount > 0 ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (discount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.remove, color: Colors.red, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            'Discount: Rs ${discount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Final Amount',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rs ${finalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),

          // Services list - Use StreamBuilder for real-time updates
          Expanded(
            child:
                provider.activeSessionId == null
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

                        // Properly convert services from Firestore
                        final servicesList = data['services'];
                        List<Map<String, dynamic>> services = [];
                        if (servicesList != null && servicesList is List) {
                          services =
                              servicesList
                                  .map((s) {
                                    if (s is Map) {
                                      return Map<String, dynamic>.from(s);
                                    }
                                    return <String, dynamic>{};
                                  })
                                  .toList()
                                  .cast<Map<String, dynamic>>();
                        }

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
                            key: ValueKey('services-${services.length}-${currentTotal}'),
                            itemCount: services.length,
                            itemBuilder: (context, index) {
                              final service = services[index];
                              final type = service['type']?.toString() ?? 'Unknown';

                              // Properly convert price from Firestore (could be int, double, or num)
                              double price = 0.0;
                              if (service['price'] != null) {
                                if (service['price'] is num) {
                                  price = (service['price'] as num).toDouble();
                                } else if (service['price'] is String) {
                                  price = double.tryParse(service['price'] as String) ?? 0.0;
                                }
                              }

                              // Get additional controllers (support both old multiplayer and new additionalControllers)
                              int additionalControllers = 0;
                              if (service['additionalControllers'] != null) {
                                additionalControllers =
                                    service['additionalControllers'] is int
                                        ? service['additionalControllers'] as int
                                        : int.tryParse(
                                              service['additionalControllers'].toString(),
                                            ) ??
                                            0;
                              } else if (service['multiplayer'] == true ||
                                  service['multiplayer'] == 'true') {
                                // Backward compatibility: convert old multiplayer to 1 additional controller
                                additionalControllers = 1;
                              }

                              // Get hours and minutes
                              int hours = 0;
                              int minutes = 0;
                              if (service['hours'] != null) {
                                hours =
                                    service['hours'] is int
                                        ? service['hours'] as int
                                        : int.tryParse(service['hours'].toString()) ?? 0;
                              }
                              if (service['minutes'] != null) {
                                minutes =
                                    service['minutes'] is int
                                        ? service['minutes'] as int
                                        : int.tryParse(service['minutes'].toString()) ?? 0;
                              }

                              String subtitle = 'Rs ${price.toStringAsFixed(2)}';
                              if (hours > 0 || minutes > 0) {
                                final controllerText =
                                    additionalControllers > 0
                                        ? ' (+$additionalControllers Controller${additionalControllers > 1 ? 's' : ''})'
                                        : '';
                                subtitle =
                                    '${hours}h ${minutes}m$controllerText - Rs ${price.toStringAsFixed(2)}';
                              } else if (service['slots'] != null && service['games'] != null) {
                                // VR Game with slots
                                final slots = service['slots'] is int 
                                    ? service['slots'] as int 
                                    : int.tryParse(service['slots'].toString()) ?? 0;
                                final games = service['games'] is int 
                                    ? service['games'] as int 
                                    : int.tryParse(service['games'].toString()) ?? 0;
                                subtitle =
                                    '$slots slot${slots != 1 ? 's' : ''} ($games games) - Rs ${price.toStringAsFixed(2)}';
                              } else if (service['duration'] != null) {
                                subtitle =
                                    '${service['duration']} min - Rs ${price.toStringAsFixed(2)}';
                              }

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: type == 'PS5' ? Colors.blue : Colors.purple,
                                    child: Text(
                                      type == 'PS5'
                                          ? 'PS5'
                                          : type == 'PS4'
                                          ? 'PS4'
                                          : type[0],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    '$type${additionalControllers > 0 ? ' (+$additionalControllers Controller${additionalControllers > 1 ? 's' : ''})' : ''}',
                                  ),
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
                BoxShadow(color: Colors.grey.shade300, blurRadius: 4, offset: const Offset(0, -2)),
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
                // Get final amount for confirmation dialog
                double finalAmount = provider.currentTotal;
                double discount = 0.0;
                final sessionDoc = await provider.sessionsRef().doc(provider.activeSessionId).get();
                if (sessionDoc.exists) {
                  final data = sessionDoc.data() as Map<String, dynamic>?;
                  finalAmount =
                      (data?['finalAmount'] ?? data?['totalAmount'] ?? provider.currentTotal)
                          .toDouble();
                  discount = (data?['discount'] ?? 0).toDouble();
                }

                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('End Session'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Amount: Rs ${provider.currentTotal.toStringAsFixed(2)}'),
                            if (discount > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Discount: Rs ${discount.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Final Amount: Rs ${finalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Text(
                              'Are you sure you want to end this session? This will add it to history.',
                            ),
                          ],
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

  const _EditDeviceDialog({required this.device, required this.onConfirm});

  @override
  State<_EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  late int hours;
  late int minutes;
  late int additionalControllers;
  double price = 0;

  @override
  void initState() {
    super.initState();
    hours = widget.device['hours'] ?? 0;
    minutes = widget.device['minutes'] ?? 0;
    // Support both old multiplayer and new additionalControllers
    if (widget.device['additionalControllers'] != null) {
      additionalControllers =
          widget.device['additionalControllers'] is int
              ? widget.device['additionalControllers'] as int
              : int.tryParse(widget.device['additionalControllers'].toString()) ?? 0;
    } else if (widget.device['multiplayer'] == true || widget.device['multiplayer'] == 'true') {
      additionalControllers = 1; // Convert old multiplayer to 1 controller
    } else {
      additionalControllers = 0;
    }
    _calculatePrice();
  }

  void _calculatePrice() async {
    if (widget.device['type'] == 'PS4') {
      price = await PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    } else if (widget.device['type'] == 'PS5') {
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
          // Additional Controllers
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Text(
                  'Additional Controllers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Rs 150 per controller',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
              children: [
                Text('Total Time: ${hours}h ${minutes}m'),
                if (additionalControllers > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Additional Controllers: $additionalControllers × Rs 150',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Controller Charge: Rs ${(additionalControllers * 150).toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                  ),
                ],
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed:
              (hours == 0 && minutes == 0)
                  ? null
                  : () {
                    widget.onConfirm({
                      ...widget.device,
                      'hours': hours,
                      'minutes': minutes,
                      'price': price,
                      'additionalControllers': additionalControllers,
                    });
                  },
          child: const Text('Update'),
        ),
      ],
    );
  }
}
