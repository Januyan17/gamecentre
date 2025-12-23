import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import 'session_detail_page.dart';

class CreateSessionPage extends StatefulWidget {
  const CreateSessionPage({super.key});

  @override
  State<CreateSessionPage> createState() => _CreateSessionPageState();
}

class _CreateSessionPageState extends State<CreateSessionPage> {
  final List<TextEditingController> _customerControllers = [TextEditingController()];

  @override
  void dispose() {
    for (var controller in _customerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addCustomer() {
    setState(() {
      _customerControllers.add(TextEditingController());
    });
  }

  void _removeCustomer(int index) {
    if (_customerControllers.length > 1) {
      setState(() {
        _customerControllers[index].dispose();
        _customerControllers.removeAt(index);
      });
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
              'Customer Names (Add multiple if needed):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _customerControllers.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customerControllers[index],
                            decoration: InputDecoration(
                              labelText: 'Customer ${index + 1}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (_customerControllers.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeCustomer(index),
                            tooltip: 'Remove customer',
                          ),
                      ],
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
                  onPressed: () async {
                    final customers = _customerControllers
                        .map((c) => c.text.trim())
                        .where((name) => name.isNotEmpty)
                        .toList();
                    
                    if (customers.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter at least one customer name')),
                      );
                      return;
                    }

                    final customerName = customers.join(', ');
                    await context.read<SessionProvider>().createSession(customerName);
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const SessionDetailPage()),
                      );
                    }
                  },
                  child: const Text('Start Session'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
