import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/price_calculator.dart';

/// Pricing Settings Page
/// 
/// IMPORTANT: This page is password-protected (password: rowzow172)
/// Only admin with correct password can change pricing.
/// 
/// Pricing settings are stored in Firestore 'settings/pricing' collection.
/// These prices are NEVER reset automatically by daily reset service.
/// Prices can ONLY be changed manually by admin through this page.
class PricingSettingsPage extends StatefulWidget {
  const PricingSettingsPage({super.key});

  @override
  State<PricingSettingsPage> createState() => _PricingSettingsPageState();
}

class _PricingSettingsPageState extends State<PricingSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Controllers for PS4 and PS5
  final TextEditingController _ps4HourlyController = TextEditingController();
  final TextEditingController _ps5HourlyController = TextEditingController();
  
  // Controllers for VR and Racing Wheel
  final TextEditingController _vrController = TextEditingController();
  final TextEditingController _racingWheelController = TextEditingController();
  
  // Controllers for Theatre (1hr, 2hr, 3hr, 4hr)
  final TextEditingController _theatre1hrController = TextEditingController();
  final TextEditingController _theatre2hrController = TextEditingController();
  final TextEditingController _theatre3hrController = TextEditingController();
  final TextEditingController _theatre4hrController = TextEditingController();
  
  // Controllers for Additional Person Charges (1hr, 2hr, 3hr, 4hr)
  final TextEditingController _person1hrController = TextEditingController();
  final TextEditingController _person2hrController = TextEditingController();
  final TextEditingController _person3hrController = TextEditingController();
  final TextEditingController _person4hrController = TextEditingController();
  
  // Additional Controller charge
  final TextEditingController _additionalControllerController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  @override
  void dispose() {
    _ps4HourlyController.dispose();
    _ps5HourlyController.dispose();
    _vrController.dispose();
    _racingWheelController.dispose();
    _theatre1hrController.dispose();
    _theatre2hrController.dispose();
    _theatre3hrController.dispose();
    _theatre4hrController.dispose();
    _person1hrController.dispose();
    _person2hrController.dispose();
    _person3hrController.dispose();
    _person4hrController.dispose();
    _additionalControllerController.dispose();
    super.dispose();
  }

  Future<void> _loadPrices() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore.collection('settings').doc('pricing').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        _ps4HourlyController.text = (data['ps4HourlyRate'] ?? 250.0).toString();
        _ps5HourlyController.text = (data['ps5HourlyRate'] ?? 350.0).toString();
        _vrController.text = (data['vr'] ?? 700).toString();
        _racingWheelController.text = (data['racingWheel'] ?? 500).toString();
        _theatre1hrController.text = (data['theatre1hr'] ?? 1500).toString();
        _theatre2hrController.text = (data['theatre2hr'] ?? 2000).toString();
        _theatre3hrController.text = (data['theatre3hr'] ?? 2500).toString();
        _theatre4hrController.text = (data['theatre4hr'] ?? 3000).toString();
        _person1hrController.text = (data['person1hr'] ?? 350).toString();
        _person2hrController.text = (data['person2hr'] ?? 350).toString();
        _person3hrController.text = (data['person3hr'] ?? 350).toString();
        _person4hrController.text = (data['person4hr'] ?? 350).toString();
        _additionalControllerController.text = (data['additionalController'] ?? 150).toString();
      } else {
        // Set default values
        _ps4HourlyController.text = '250';
        _ps5HourlyController.text = '350';
        _vrController.text = '700';
        _racingWheelController.text = '500';
        _theatre1hrController.text = '1500';
        _theatre2hrController.text = '2000';
        _theatre3hrController.text = '2500';
        _theatre4hrController.text = '3000';
        _person1hrController.text = '350';
        _person2hrController.text = '350';
        _person3hrController.text = '350';
        _person4hrController.text = '350';
        _additionalControllerController.text = '150';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading prices: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePrices() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('settings').doc('pricing').set({
        'ps4HourlyRate': double.parse(_ps4HourlyController.text),
        'ps5HourlyRate': double.parse(_ps5HourlyController.text),
        'vr': double.parse(_vrController.text),
        'racingWheel': double.parse(_racingWheelController.text),
        'theatre1hr': double.parse(_theatre1hrController.text),
        'theatre2hr': double.parse(_theatre2hrController.text),
        'theatre3hr': double.parse(_theatre3hrController.text),
        'theatre4hr': double.parse(_theatre4hrController.text),
        'person1hr': double.parse(_person1hrController.text),
        'person2hr': double.parse(_person2hrController.text),
        'person3hr': double.parse(_person3hrController.text),
        'person4hr': double.parse(_person4hrController.text),
        'additionalController': double.parse(_additionalControllerController.text),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Clear price cache so new prices are loaded
      PriceCalculator.clearCache();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prices saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving prices: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          prefixText: 'Rs ',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter a price';
          }
          final price = double.tryParse(value);
          if (price == null || price < 0) {
            return 'Please enter a valid price';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing Settings'),
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
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _savePrices,
              tooltip: 'Save Prices',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Console Prices
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Console Prices (Per Hour)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              label: 'PS4 Hourly Rate',
                              controller: _ps4HourlyController,
                            ),
                            _buildTextField(
                              label: 'PS5 Hourly Rate',
                              controller: _ps5HourlyController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Additional Controller
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Additional Controller',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              label: 'Additional Controller Charge (per controller)',
                              controller: _additionalControllerController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // VR and Racing Wheel
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Other Services',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              label: 'VR Game (20 min)',
                              controller: _vrController,
                            ),
                            _buildTextField(
                              label: 'Racing Wheel / Car Simulator (30 min)',
                              controller: _racingWheelController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Theatre Prices
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Private Theatre Base Prices',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              label: '1 Hour',
                              controller: _theatre1hrController,
                            ),
                            _buildTextField(
                              label: '2 Hours',
                              controller: _theatre2hrController,
                            ),
                            _buildTextField(
                              label: '3 Hours',
                              controller: _theatre3hrController,
                            ),
                            _buildTextField(
                              label: '4 Hours',
                              controller: _theatre4hrController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Additional Person Charges
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Additional Person Charges (Per Person)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              label: '1 Hour',
                              controller: _person1hrController,
                            ),
                            _buildTextField(
                              label: '2 Hours',
                              controller: _person2hrController,
                            ),
                            _buildTextField(
                              label: '3 Hours',
                              controller: _person3hrController,
                            ),
                            _buildTextField(
                              label: '4 Hours',
                              controller: _person4hrController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _savePrices,
                        icon: const Icon(Icons.save),
                        label: const Text('Save All Prices'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

