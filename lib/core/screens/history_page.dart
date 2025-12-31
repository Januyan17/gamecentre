import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:rowzow/core/services/firebase_service.dart';
import 'package:rowzow/core/services/session_service.dart';
import 'package:rowzow/core/services/price_calculator.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime selectedDate = DateTime.now();
  final SessionService _sessionService = SessionService();
  final FirebaseService _fs = FirebaseService();

  @override
  Widget build(BuildContext context) {
    final dateId = DateFormat('yyyy-MM-dd').format(selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Date: ${DateFormat('MMM dd, yyyy').format(selectedDate)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Change'),
                ),
              ],
            ),
          ),

          // History list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _fs.historySessionsRef(dateId).snapshots(),
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
                          'No sessions found for this date',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildSessionCard(doc.id, data, dateId);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(String sessionId, Map<String, dynamic> data, String dateId) {
    final customerName = data['customerName'] ?? 'Unknown';
    // Use finalAmount if discount exists, otherwise use totalAmount
    final totalAmount = (data['finalAmount'] ?? data['totalAmount'] ?? 0).toDouble();
    final services = List<Map<String, dynamic>>.from(data['services'] ?? []);
    final startTime = data['startTime'] as Timestamp?;
    final endTime = data['endTime'] as Timestamp?;

    String timeInfo = '';
    if (startTime != null) {
      timeInfo = DateFormat('hh:mm a').format(startTime.toDate());
      if (endTime != null) {
        timeInfo += ' - ${DateFormat('hh:mm a').format(endTime.toDate())}';
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue,
          child: Text(
            customerName[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: Rs ${totalAmount.toStringAsFixed(2)}'),
            if (timeInfo.isNotEmpty)
              Text(timeInfo, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _editSession(sessionId, data, dateId),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteSession(sessionId, totalAmount, dateId, customerName),
              tooltip: 'Delete',
            ),
          ],
        ),
        children: [
          if (services.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No services in this session', style: TextStyle(color: Colors.grey)),
            )
          else
            ...services.map((service) {
              final type = service['type'] ?? 'Unknown';
              final price = (service['price'] ?? 0).toDouble();
              String subtitle = 'Rs ${price.toStringAsFixed(2)}';

              // Get additional controllers (support both old multiplayer and new additionalControllers)
              int additionalControllers = 0;
              if (service['additionalControllers'] != null) {
                additionalControllers =
                    service['additionalControllers'] is int
                        ? service['additionalControllers'] as int
                        : int.tryParse(service['additionalControllers'].toString()) ?? 0;
              } else if (service['multiplayer'] == true || service['multiplayer'] == 'true') {
                // Backward compatibility: convert old multiplayer to 1 additional controller
                additionalControllers = 1;
              }

              if (service['hours'] != null && service['minutes'] != null) {
                final controllerText =
                    additionalControllers > 0
                        ? ' (+$additionalControllers Controller${additionalControllers > 1 ? 's' : ''})'
                        : '';
                subtitle =
                    '${service['hours']}h ${service['minutes']}m$controllerText - Rs ${price.toStringAsFixed(2)}';
              } else if (service['duration'] != null) {
                subtitle = '${service['duration']} min - Rs ${price.toStringAsFixed(2)}';
              }

              return ListTile(
                dense: true,
                leading: Icon(
                  type == 'PS5' ? Icons.sports_esports : Icons.videogame_asset,
                  color: type == 'PS5' ? Colors.blue : Colors.purple,
                ),
                title: Text(
                  '$type${additionalControllers > 0 ? ' (+$additionalControllers Controller${additionalControllers > 1 ? 's' : ''})' : ''}',
                ),
                subtitle: Text(subtitle),
              );
            }).toList(),
        ],
      ),
    );
  }

  void _editSession(String sessionId, Map<String, dynamic> data, String dateId) {
    showDialog(
      context: context,
      builder:
          (context) => _EditHistorySessionDialog(
            sessionId: sessionId,
            data: data,
            dateId: dateId,
            onUpdated: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Session updated successfully')));
            },
          ),
    );
  }

  void _deleteSession(String sessionId, double amount, String dateId, String customerName) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete Session'),
            content: Text(
              'Are you sure you want to delete this session?\n\n'
              'Customer: $customerName\n'
              'Amount: Rs ${amount.toStringAsFixed(2)}\n\n'
              'This action cannot be undone. The session will be permanently deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogContext); // Close confirmation dialog

                  // Store the navigator before async operations
                  final navigator = Navigator.of(context, rootNavigator: true);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);

                  // Show loading
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (loadingContext) => PopScope(
                          canPop: false,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                  );

                  try {
                    await _sessionService.deleteHistorySession(dateId, sessionId, amount);

                    // Wait a bit to ensure Firestore updates
                    await Future.delayed(const Duration(milliseconds: 500));

                    // Close loading dialog using root navigator
                    if (navigator.canPop()) {
                      navigator.pop();
                    }

                    // Wait a bit for the loading dialog to fully close before showing snackbar
                    await Future.delayed(const Duration(milliseconds: 200));

                    // Show success message
                    if (context.mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.white),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Session deleted successfully',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 3),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    }
                  } catch (e) {
                    // Close loading dialog using root navigator
                    if (navigator.canPop()) {
                      navigator.pop();
                    }

                    // Wait a bit for the loading dialog to fully close before showing snackbar
                    await Future.delayed(const Duration(milliseconds: 200));

                    if (context.mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.error, color: Colors.white),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Error deleting session: ${e.toString()}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }
}

class _EditHistorySessionDialog extends StatefulWidget {
  final String sessionId;
  final Map<String, dynamic> data;
  final String dateId;
  final VoidCallback onUpdated;

  const _EditHistorySessionDialog({
    required this.sessionId,
    required this.data,
    required this.dateId,
    required this.onUpdated,
  });

  @override
  State<_EditHistorySessionDialog> createState() => _EditHistorySessionDialogState();
}

class _EditHistorySessionDialogState extends State<_EditHistorySessionDialog> {
  late TextEditingController _nameController;
  late List<Map<String, dynamic>> _services;
  final SessionService _sessionService = SessionService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data['customerName'] ?? '');
    _services = List<Map<String, dynamic>>.from(widget.data['services'] ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _editService(int index) {
    final service = _services[index];
    if (service['type'] == 'PS4' || service['type'] == 'PS5') {
      showDialog(
        context: context,
        builder:
            (context) => _EditServiceTimeDialog(
              service: service,
              onConfirm: (updated) {
                setState(() {
                  _services[index] = updated;
                  _recalculateTotal();
                });
                Navigator.pop(context);
              },
            ),
      );
    }
  }

  void _deleteService(int index) {
    setState(() {
      _services.removeAt(index);
      _recalculateTotal();
    });
  }

  void _recalculateTotal() {
    setState(() {});
  }

  double _getTotal() {
    return _services.fold<double>(0, (sum, service) => sum + (service['price'] as num).toDouble());
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter customer name')));
      return;
    }

    final total = _getTotal();
    await _sessionService.updateHistorySession(widget.dateId, widget.sessionId, {
      'customerName': _nameController.text.trim(),
      'services': _services,
      'totalAmount': total,
    });

    // Update day totals
    final oldTotal = (widget.data['totalAmount'] ?? 0).toDouble();
    final diff = total - oldTotal;

    if (diff != 0) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final dayRef = FirebaseFirestore.instance.collection('days').doc(widget.dateId);

        final dayDoc = await tx.get(dayRef);
        if (dayDoc.exists) {
          final dayData = dayDoc.data();
          final currentTotal = ((dayData as Map<String, dynamic>)['totalAmount'] ?? 0).toDouble();
          tx.update(dayRef, {'totalAmount': (currentTotal + diff).clamp(0.0, double.infinity)});
        }
      });
    }

    widget.onUpdated();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Services:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_services.isEmpty)
              const Text('No services', style: TextStyle(color: Colors.grey))
            else
              ...List.generate(_services.length, (index) {
                final service = _services[index];
                final type = service['type'] ?? 'Unknown';
                final price = (service['price'] ?? 0).toDouble();

                // Get additional controllers (support both old multiplayer and new additionalControllers)
                int additionalControllers = 0;
                if (service['additionalControllers'] != null) {
                  additionalControllers =
                      service['additionalControllers'] is int
                          ? service['additionalControllers'] as int
                          : int.tryParse(service['additionalControllers'].toString()) ?? 0;
                } else if (service['multiplayer'] == true || service['multiplayer'] == 'true') {
                  // Backward compatibility: convert old multiplayer to 1 additional controller
                  additionalControllers = 1;
                }

                String subtitle = 'Rs ${price.toStringAsFixed(2)}';

                if (service['hours'] != null && service['minutes'] != null) {
                  final controllerText =
                      additionalControllers > 0
                          ? ' (+$additionalControllers Controller${additionalControllers > 1 ? 's' : ''})'
                          : '';
                  subtitle =
                      '${service['hours']}h ${service['minutes']}m$controllerText - Rs ${price.toStringAsFixed(2)}';
                }

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(
                      '$type${additionalControllers > 0 ? ' (+$additionalControllers Controller${additionalControllers > 1 ? 's' : ''})' : ''}',
                    ),
                    subtitle: Text(subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (type == 'PS4' || type == 'PS5')
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editService(index),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () => _deleteService(index),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    'Rs ${_getTotal().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _EditServiceTimeDialog extends StatefulWidget {
  final Map<String, dynamic> service;
  final Function(Map<String, dynamic>) onConfirm;

  const _EditServiceTimeDialog({required this.service, required this.onConfirm});

  @override
  State<_EditServiceTimeDialog> createState() => _EditServiceTimeDialogState();
}

class _EditServiceTimeDialogState extends State<_EditServiceTimeDialog> {
  late int hours;
  late int minutes;
  late int additionalControllers;
  double price = 0;

  @override
  void initState() {
    super.initState();
    hours = widget.service['hours'] ?? 0;
    minutes = widget.service['minutes'] ?? 0;
    // Support both old multiplayer and new additionalControllers
    if (widget.service['additionalControllers'] != null) {
      additionalControllers =
          widget.service['additionalControllers'] is int
              ? widget.service['additionalControllers'] as int
              : int.tryParse(widget.service['additionalControllers'].toString()) ?? 0;
    } else if (widget.service['multiplayer'] == true || widget.service['multiplayer'] == 'true') {
      additionalControllers = 1; // Convert old multiplayer to 1 controller
    } else {
      additionalControllers = 0;
    }
    _calculatePrice();
  }

  void _calculatePrice() async {
    if (widget.service['type'] == 'PS4') {
      price = await PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    } else if (widget.service['type'] == 'PS5') {
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
      title: Text('Edit ${widget.service['type']}'),
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
                Text('Total Time: ${hours}h ${minutes}m', style: const TextStyle(fontSize: 16)),
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
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
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
                      ...widget.service,
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
