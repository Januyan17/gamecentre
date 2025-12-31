import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rowzow/core/services/price_calculator.dart';
import '../providers/session_provider.dart';

class AddServicePage extends StatelessWidget {
  const AddServicePage({super.key});

  void _add(BuildContext context, Map<String, dynamic> service) {
    context.read<SessionProvider>().addService(service);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Service')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Note: PS4 and PS5 should be added from the "Add Device" button with time selection.',
            style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          const Divider(),

          const Text('VR Game (20 min)', style: TextStyle(fontSize: 18)),
          ElevatedButton(
            onPressed: () async {
              final price = await PriceCalculator.vr();
              _add(context, {'type': 'VR', 'duration': 20, 'price': price});
            },
            child: const Text('Add VR Session'),
          ),

          const Divider(),

          const Text('Car Simulator (30 min)', style: TextStyle(fontSize: 18)),
          ElevatedButton(
            onPressed: () async {
              final price = await PriceCalculator.carSimulator();
              _add(context, {
                'type': 'Simulator',
                'duration': 30,
                'price': price,
                'startTime': DateTime.now().toIso8601String(),
              });
            },
            child: const Text('Add Simulator Session'),
          ),

          const Divider(),

          const Text('Private Theatre', style: TextStyle(fontSize: 18)),
          ElevatedButton(
            onPressed: () => _openTheatreDialog(context),
            child: const Text('Add Theatre'),
          ),
        ],
      ),
    );
  }

  void _openTheatreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _TheatreDialog(
        onAdd: (hours, people, price) {
          _add(context, {
            'type': 'Theatre',
            'hours': hours,
            'people': people,
            'price': price,
            'startTime': DateTime.now().toIso8601String(),
          });
        },
      ),
    );
  }
}

class _TheatreDialog extends StatefulWidget {
  final Function(int hours, int people, int price) onAdd;

  const _TheatreDialog({required this.onAdd});

  @override
  State<_TheatreDialog> createState() => _TheatreDialogState();
}

class _TheatreDialogState extends State<_TheatreDialog> {
  int _hours = 1;
  final TextEditingController _peopleController = TextEditingController(text: '4');
  double _price = 0.0;

  @override
  void initState() {
    super.initState();
    _updatePrice();
  }

  @override
  void dispose() {
    _peopleController.dispose();
    super.dispose();
  }

  Future<void> _updatePrice() async {
    final people = int.tryParse(_peopleController.text) ?? 4;
    final price = await PriceCalculator.theatre(
      hours: _hours,
      people: people.clamp(1, 10),
    );
    if (mounted) {
      setState(() => _price = price);
    }
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: const Text('Theatre Booking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Duration:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _hours,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 Hour')),
              DropdownMenuItem(value: 2, child: Text('2 Hours')),
              DropdownMenuItem(value: 3, child: Text('3 Hours')),
              DropdownMenuItem(value: 4, child: Text('4 Hours')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _hours = value;
                });
                _updatePrice();
              }
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Number of People:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _peopleController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: InputDecoration(
              labelText: 'People (max 10)',
              border: const OutlineInputBorder(),
              helperText: 'Maximum 10 people',
            ),
            onChanged: (value) {
              _updatePrice();
            },
          ),
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
                const Text(
                  'Total Price:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Rs ${_price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final peopleCount = int.tryParse(_peopleController.text) ?? 4;
            final finalPrice = await PriceCalculator.theatre(
              hours: _hours,
              people: peopleCount.clamp(1, 10),
            );

            widget.onAdd(_hours, peopleCount.clamp(1, 10), finalPrice.toInt());
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
