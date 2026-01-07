import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/price_calculator.dart';
import 'common_scenarios_page.dart';

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
  final TextEditingController _additionalControllerController =
      TextEditingController();

  // Device Capacity Controllers
  final TextEditingController _ps5CountController = TextEditingController();
  final TextEditingController _ps4CountController = TextEditingController();
  final TextEditingController _vrCountController = TextEditingController();
  final TextEditingController _simulatorCountController =
      TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  bool _ps4NotificationsEnabled = true;
  bool _ps5NotificationsEnabled = true;
  bool _vrNotificationsEnabled = true;
  bool _simulatorNotificationsEnabled = true;
  bool _theatreNotificationsEnabled = true;

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
    _ps5CountController.dispose();
    _ps4CountController.dispose();
    _vrCountController.dispose();
    _simulatorCountController.dispose();
    super.dispose();
  }

  Future<void> _loadPrices() async {
    setState(() => _isLoading = true);
    try {
      // Load pricing
      final pricingDoc =
          await _firestore.collection('settings').doc('pricing').get();
      if (pricingDoc.exists) {
        final data = pricingDoc.data() as Map<String, dynamic>;

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
        _additionalControllerController.text =
            (data['additionalController'] ?? 150).toString();
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

      // Load device capacity settings
      final capacityDoc =
          await _firestore.collection('settings').doc('device_capacity').get();
      if (capacityDoc.exists) {
        final capacityData = capacityDoc.data() as Map<String, dynamic>;
        _ps5CountController.text = (capacityData['ps5Count'] ?? 0).toString();
        _ps4CountController.text = (capacityData['ps4Count'] ?? 0).toString();
        _vrCountController.text = (capacityData['vrCount'] ?? 0).toString();
        _simulatorCountController.text =
            (capacityData['simulatorCount'] ?? 0).toString();
      } else {
        // Set default values
        _ps5CountController.text = '0';
        _ps4CountController.text = '0';
        _vrCountController.text = '0';
        _simulatorCountController.text = '0';
      }

      // Load notification settings
      final notificationDoc =
          await _firestore.collection('settings').doc('notifications').get();
      if (notificationDoc.exists) {
        final data = notificationDoc.data() as Map<String, dynamic>;
        setState(() {
          _ps4NotificationsEnabled = data['ps4'] ?? true;
          _ps5NotificationsEnabled = data['ps5'] ?? true;
          _vrNotificationsEnabled = data['vr'] ?? true;
          _simulatorNotificationsEnabled = data['simulator'] ?? true;
          _theatreNotificationsEnabled = data['theatre'] ?? true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading settings: $e')));
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
        'additionalController': double.parse(
          _additionalControllerController.text,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Save device capacity settings
      await _firestore.collection('settings').doc('device_capacity').set({
        'ps5Count': int.parse(_ps5CountController.text),
        'ps4Count': int.parse(_ps4CountController.text),
        'vrCount': int.parse(_vrCountController.text),
        'simulatorCount': int.parse(_simulatorCountController.text),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Clear price cache so new prices are loaded
      PriceCalculator.clearCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prices and device capacity saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveNotificationSetting(
    String serviceType,
    bool enabled,
  ) async {
    try {
      await _firestore.collection('settings').doc('notifications').set({
        serviceType: enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? '$serviceType notifications enabled'
                  : '$serviceType notifications disabled',
            ),
            backgroundColor: enabled ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving notification setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildNotificationToggle(
    String serviceName,
    bool value,
    Function(bool) onChanged,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Text(
                serviceName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Switch(value: value, onChanged: onChanged, activeColor: color),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? prefixText,
    bool isInteger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          prefixText: prefixText,
        ),
        keyboardType: TextInputType.number,
        inputFormatters:
            isInteger
                ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+'))]
                : [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter a value';
          }
          if (isInteger) {
            final intValue = int.tryParse(value);
            if (intValue == null || intValue < 0) {
              return 'Please enter a valid number (0 or greater)';
            }
          } else {
            final price = double.tryParse(value);
            if (price == null || price < 0) {
              return 'Please enter a valid price';
            }
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
          IconButton(
            icon: const Icon(Icons.settings_applications),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CommonScenariosPage()),
              );
            },
            tooltip: 'Manage Common Scenarios',
          ),
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
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Notification Settings
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.notifications_active,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Notification Settings',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enable notifications for each service type',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildNotificationToggle(
                                'PS4',
                                _ps4NotificationsEnabled,
                                (value) async {
                                  setState(() {
                                    _ps4NotificationsEnabled = value;
                                  });
                                  await _saveNotificationSetting('ps4', value);
                                },
                                Colors.blue,
                              ),
                              const SizedBox(height: 12),
                              _buildNotificationToggle(
                                'PS5',
                                _ps5NotificationsEnabled,
                                (value) async {
                                  setState(() {
                                    _ps5NotificationsEnabled = value;
                                  });
                                  await _saveNotificationSetting('ps5', value);
                                },
                                Colors.blue,
                              ),
                              const SizedBox(height: 12),
                              _buildNotificationToggle(
                                'VR',
                                _vrNotificationsEnabled,
                                (value) async {
                                  setState(() {
                                    _vrNotificationsEnabled = value;
                                  });
                                  await _saveNotificationSetting('vr', value);
                                },
                                Colors.purple,
                              ),
                              const SizedBox(height: 12),
                              _buildNotificationToggle(
                                'Simulator',
                                _simulatorNotificationsEnabled,
                                (value) async {
                                  setState(() {
                                    _simulatorNotificationsEnabled = value;
                                  });
                                  await _saveNotificationSetting(
                                    'simulator',
                                    value,
                                  );
                                },
                                Colors.orange,
                              ),
                              const SizedBox(height: 12),
                              _buildNotificationToggle(
                                'Theatre',
                                _theatreNotificationsEnabled,
                                (value) async {
                                  setState(() {
                                    _theatreNotificationsEnabled = value;
                                  });
                                  await _saveNotificationSetting(
                                    'theatre',
                                    value,
                                  );
                                },
                                Colors.red,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: 'PS5 Hourly Rate',
                                controller: _ps5HourlyController,
                                prefixText: 'Rs ',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Device Capacity Settings
                      Card(
                        color: Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.devices,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Device Capacity',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Set the total number of available devices. This controls how many parallel bookings can be made for each device type.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                label: 'PS5 Count',
                                controller: _ps5CountController,
                                hint: 'Number of PS5 units available',
                                isInteger: true,
                              ),
                              _buildTextField(
                                label: 'PS4 Count',
                                controller: _ps4CountController,
                                hint: 'Number of PS4 units available',
                                isInteger: true,
                              ),
                              _buildTextField(
                                label: 'VR Count',
                                controller: _vrCountController,
                                hint: 'Number of VR units available',
                                isInteger: true,
                              ),
                              _buildTextField(
                                label: 'Simulator Count',
                                controller: _simulatorCountController,
                                hint:
                                    'Number of Racing Simulator units available',
                                isInteger: true,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Setting count to 0 disables capacity checking (unlimited bookings). '
                                        'Reducing capacity will prevent new bookings beyond the limit, but existing active sessions remain intact.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                                label:
                                    'Additional Controller Charge (per controller)',
                                controller: _additionalControllerController,
                                prefixText: 'Rs ',
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
                                label: 'VR Game Slot (2 games per slot)',
                                controller: _vrController,
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label:
                                    'Racing Wheel / Car Simulator (per game)',
                                controller: _racingWheelController,
                                prefixText: 'Rs ',
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
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: '2 Hours',
                                controller: _theatre2hrController,
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: '3 Hours',
                                controller: _theatre3hrController,
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: '4 Hours',
                                controller: _theatre4hrController,
                                prefixText: 'Rs ',
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
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: '2 Hours',
                                controller: _person2hrController,
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: '3 Hours',
                                controller: _person3hrController,
                                prefixText: 'Rs ',
                              ),
                              _buildTextField(
                                label: '4 Hours',
                                controller: _person4hrController,
                                prefixText: 'Rs ',
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
