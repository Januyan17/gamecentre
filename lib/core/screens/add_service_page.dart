import 'package:flutter/material.dart';
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
            onPressed:
                () => _add(context, {'type': 'VR', 'duration': 20, 'price': PriceCalculator.vr()}),
            child: const Text('Add VR Session'),
          ),

          const Divider(),

          const Text('Car Simulator (30 min)', style: TextStyle(fontSize: 18)),
          ElevatedButton(
            onPressed:
                () => _add(context, {
                  'type': 'Simulator',
                  'duration': 30,
                  'price': PriceCalculator.carSimulator(),
                }),
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
    int hours = 1;
    int people = 4;

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Theatre Booking'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<int>(
                  value: hours,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Hour')),
                    DropdownMenuItem(value: 2, child: Text('2 Hours')),
                    DropdownMenuItem(value: 3, child: Text('3 Hours')),
                  ],
                  onChanged: (v) => hours = v!,
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'People (max 10)'),
                  onChanged: (v) => people = int.tryParse(v) ?? 4,
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Add'),
                onPressed: () {
                  final price = PriceCalculator.theatre(hours: hours, people: people.clamp(1, 10));

                  _add(context, {
                    'type': 'Theatre',
                    'hours': hours,
                    'people': people,
                    'price': price,
                  });

                  Navigator.pop(context);
                },
              ),
            ],
          ),
    );
  }
}
