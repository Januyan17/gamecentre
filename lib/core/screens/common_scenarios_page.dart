import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/price_calculator.dart';

/// Common Scenarios Management Page
/// 
/// Admin can configure common scenarios that appear as quick-add buttons
/// in the device selection page.
class CommonScenariosPage extends StatefulWidget {
  const CommonScenariosPage({super.key});

  @override
  State<CommonScenariosPage> createState() => _CommonScenariosPageState();
}

class _CommonScenariosPageState extends State<CommonScenariosPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSaving = false;

  // Helper method to get scenarios stream with error handling
  Stream<QuerySnapshot> _getScenariosStream() {
    try {
      return _firestore
          .collection('common_scenarios')
          .orderBy('order', descending: false)
          .snapshots();
    } catch (e) {
      // If order index doesn't exist, return stream without orderBy
      debugPrint('Order index not found, using stream without order: $e');
      return _firestore.collection('common_scenarios').snapshots();
    }
  }

  // Helper method to parse scenarios from snapshot
  List<Map<String, dynamic>> _parseScenarios(QuerySnapshot? snapshot) {
    if (snapshot == null || snapshot.docs.isEmpty) {
      return [];
    }

    List<QueryDocumentSnapshot> docs = snapshot.docs.toList();
    
    // Sort manually if orderBy failed
    try {
      docs.sort((a, b) {
        final orderA = (a.data() as Map<String, dynamic>)['order'] as int? ?? 0;
        final orderB = (b.data() as Map<String, dynamic>)['order'] as int? ?? 0;
        return orderA.compareTo(orderB);
      });
    } catch (e) {
      debugPrint('Error sorting scenarios: $e');
    }

    return docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'type': data['type'] ?? 'PS5',
        'count': data['count'] ?? 1,
        'hours': data['hours'] ?? 1,
        'minutes': data['minutes'] ?? 0,
        'additionalControllers': data['additionalControllers'] ?? 0,
        'label': data['label'] ?? '',
      };
    }).toList();
  }

  Future<void> _saveScenario(Map<String, dynamic> scenario, int? index) async {
    setState(() => _isSaving = true);
    try {
      final scenarioData = {
        'type': scenario['type']?.toString() ?? 'PS5',
        'count': (scenario['count'] as num?)?.toInt() ?? 1,
        'hours': (scenario['hours'] as num?)?.toInt() ?? 1,
        'minutes': (scenario['minutes'] as num?)?.toInt() ?? 0,
        'additionalControllers': (scenario['additionalControllers'] as num?)?.toInt() ?? 0,
        'label': scenario['label']?.toString() ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (scenario['id'] != null) {
        // Update existing scenario
        if (index != null) {
          scenarioData['order'] = index;
        }
        await _firestore.collection('common_scenarios').doc(scenario['id'] as String).update(scenarioData);
      } else {
        // Create new scenario - get current count to set order
        final snapshot = await _firestore.collection('common_scenarios').get();
        scenarioData['order'] = snapshot.docs.length;
        scenarioData['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('common_scenarios').add(scenarioData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(scenario['id'] != null ? 'Scenario updated' : 'Scenario added'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving scenario: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving scenario: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }


  void _addScenario() {
    showDialog(
      context: context,
      builder: (context) => _AddScenarioDialog(
        onAdd: (scenario) async {
          Navigator.pop(context);
          // Save immediately to Firestore
          await _saveScenario(scenario, null);
        },
      ),
    );
  }

  void _editScenario(Map<String, dynamic> scenario, int index) {
    showDialog(
      context: context,
      builder: (context) => _AddScenarioDialog(
        initialScenario: scenario,
        onAdd: (updatedScenario) async {
          Navigator.pop(context);
          // Preserve the ID if editing
          if (scenario['id'] != null) {
            updatedScenario['id'] = scenario['id'];
          }
          // Save immediately to Firestore
          await _saveScenario(updatedScenario, index);
        },
      ),
    );
  }

  Future<double> _calculateScenarioPrice(String type, int hours, int minutes, int additionalControllers) async {
    if (type == 'PS4') {
      return await PriceCalculator.ps4Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    } else if (type == 'PS5') {
      return await PriceCalculator.ps5Price(
        hours: hours,
        minutes: minutes,
        additionalControllers: additionalControllers,
      );
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Common Scenarios'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getScenariosStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading scenarios: ${snapshot.error}',
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final scenarios = _parseScenarios(snapshot.data);

          return Column(
            children: [
              // Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blue.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Common Scenarios',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configure quick-add buttons for common gaming scenarios.\n'
                      'Example: 2 PS5 consoles for 2 hours with multiplayer.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              // Scenarios List
              Expanded(
                child: scenarios.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No scenarios configured',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap the + button to add a scenario',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: scenarios.length,
                        itemBuilder: (context, index) {
                          final scenario = scenarios[index];
                          final type = scenario['type'] as String? ?? 'PS5';
                          final count = (scenario['count'] as num?)?.toInt() ?? 1;
                          final hours = (scenario['hours'] as num?)?.toInt() ?? 1;
                          final minutes = (scenario['minutes'] as num?)?.toInt() ?? 0;
                          final additionalControllers = (scenario['additionalControllers'] as num?)?.toInt() ?? 0;
                          final label = scenario['label'] as String? ?? 
                              '$count $type - ${hours}h${minutes > 0 ? ' ${minutes}m' : ''}${additionalControllers > 0 ? ' (Multi)' : ''}';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: type == 'PS5' ? Colors.blue : Colors.purple,
                                child: Text(
                                  type,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                label,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '$count console${count != 1 ? 's' : ''} • ${hours}h${minutes > 0 ? ' ${minutes}m' : ''}${additionalControllers > 0 ? ' • +$additionalControllers Controller${additionalControllers > 1 ? 's' : ''}' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editScenario(scenario, index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteScenario(scenario['id'] as String?),
                                  ),
                                ],
                              ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: FutureBuilder<double>(
                                      future: _calculateScenarioPrice(type, hours, minutes, additionalControllers),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.waiting) {
                                          return const Center(child: CircularProgressIndicator());
                                        }
                                        final singlePrice = snapshot.data ?? 0.0;
                                        final totalPrice = singlePrice * count;
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Price Breakdown:',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.blue.shade800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      const Text('Price per Console:'),
                                                      Text(
                                                        'Rs ${singlePrice.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text('Number of Consoles: $count'),
                                                      const Text('×'),
                                                    ],
                                                  ),
                                                  const Divider(),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'Total Price:',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.green.shade700,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Rs ${totalPrice.toStringAsFixed(2)}',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.green.shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addScenario,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _deleteScenario(String? scenarioId) async {
    if (scenarioId == null) return;
    
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 16.0 : 24.0,
          vertical: 24.0,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: isSmallScreen ? screenSize.width * 0.9 : 400.0,
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Delete Scenario',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Are you sure you want to delete this scenario?'),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await _firestore.collection('common_scenarios').doc(scenarioId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Scenario deleted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting scenario: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting scenario: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class _AddScenarioDialog extends StatefulWidget {
  final Map<String, dynamic>? initialScenario;
  final Function(Map<String, dynamic>) onAdd;

  const _AddScenarioDialog({
    this.initialScenario,
    required this.onAdd,
  });

  @override
  State<_AddScenarioDialog> createState() => _AddScenarioDialogState();
}

class _AddScenarioDialogState extends State<_AddScenarioDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  String _type = 'PS5';
  int _count = 2;
  int _hours = 1;
  int _minutes = 0;
  int _additionalControllers = 0;
  double _singlePrice = 0.0;
  bool _calculatingPrice = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialScenario != null) {
      final s = widget.initialScenario!;
      _type = s['type'] as String? ?? 'PS5';
      _count = (s['count'] as num?)?.toInt() ?? 2;
      _hours = (s['hours'] as num?)?.toInt() ?? 1;
      _minutes = (s['minutes'] as num?)?.toInt() ?? 0;
      _additionalControllers = (s['additionalControllers'] as num?)?.toInt() ?? 0;
      _labelController.text = s['label'] as String? ?? '';
    }
    _calculatePrice();
  }

  Future<void> _calculatePrice() async {
    setState(() => _calculatingPrice = true);
    try {
      if (_type == 'PS4') {
        _singlePrice = await PriceCalculator.ps4Price(
          hours: _hours,
          minutes: _minutes,
          additionalControllers: _additionalControllers,
        );
      } else if (_type == 'PS5') {
        _singlePrice = await PriceCalculator.ps5Price(
          hours: _hours,
          minutes: _minutes,
          additionalControllers: _additionalControllers,
        );
      }
    } catch (e) {
      _singlePrice = 0.0;
    } finally {
      setState(() => _calculatingPrice = false);
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _save() {
    // Validate that at least hours or minutes is set
    if (_hours == 0 && _minutes == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set at least 1 hour or some minutes'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.onAdd({
      'type': _type,
      'count': _count,
      'hours': _hours,
      'minutes': _minutes,
      'additionalControllers': _additionalControllers,
      'label': _labelController.text.trim().isEmpty
          ? '$_count $_type - ${_hours}h${_minutes > 0 ? ' ${_minutes}m' : ''}${_additionalControllers > 0 ? ' Multi' : ''}'
          : _labelController.text.trim(),
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final dialogWidth = isSmallScreen ? screenSize.width * 0.95 : 500.0;
    final dialogMaxHeight = screenSize.height * 0.8;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8.0 : 24.0,
        vertical: 24.0,
      ),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initialScenario == null ? 'Add Scenario' : 'Edit Scenario',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Label
                TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g., 2 PS5 2h Multi',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Console Type
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Console Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'PS5', child: Text('PS5')),
                  DropdownMenuItem(value: 'PS4', child: Text('PS4')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _type = value);
                    _calculatePrice();
                  }
                },
              ),
              const SizedBox(height: 16),
              // Number of Consoles
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Number of Consoles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          if (_count > 1) {
                            setState(() => _count--);
                          }
                        },
                      ),
                      Container(
                        width: 60,
                        alignment: Alignment.center,
                        child: Text('$_count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          setState(() => _count++);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Time Selection
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                if (_hours > 0) {
                                  setState(() {
                                    _hours--;
                                    _calculatePrice();
                                  });
                                }
                              },
                            ),
                            Container(
                              width: 50,
                              alignment: Alignment.center,
                              child: Text('$_hours', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                setState(() {
                                  _hours++;
                                  _calculatePrice();
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Minutes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                if (_minutes > 0) {
                                  setState(() {
                                    _minutes -= 15;
                                    if (_minutes < 0) _minutes = 0;
                                    _calculatePrice();
                                  });
                                }
                              },
                            ),
                            Container(
                              width: 50,
                              alignment: Alignment.center,
                              child: Text('$_minutes', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                setState(() {
                                  _minutes += 15;
                                  if (_minutes >= 60) {
                                    _hours += _minutes ~/ 60;
                                    _minutes = _minutes % 60;
                                  }
                                  _calculatePrice();
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Additional Controllers
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Additional Controllers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                      Container(
                        width: 60,
                        alignment: Alignment.center,
                        child: Text('$_additionalControllers', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
              ),
              const SizedBox(height: 16),
              // Price Display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _calculatingPrice
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Price per Console: Rs ${_singlePrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total for $_count Console${_count != 1 ? 's' : ''}: Rs ${(_singlePrice * _count).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
              ),
            ),
            // Footer with actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

