import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<TextEditingController> _mobileControllers = [TextEditingController()];
  bool _isCreating = false;

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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error creating session: ${e.toString()}'),
                                    backgroundColor: Colors.red,
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
