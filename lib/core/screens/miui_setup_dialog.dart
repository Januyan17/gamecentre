import 'package:flutter/material.dart';
import 'package:rowzow/core/services/notification_service.dart';

class MiuiSetupDialog extends StatelessWidget {
  const MiuiSetupDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'MIUI Setup Required',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'For notifications to work when app is closed on MIUI devices (Redmi, Mi, Poco), you MUST complete these steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStep(
              '1',
              'Enable Autostart (MOST IMPORTANT)',
              'Tap button below → Turn ON autostart',
              Colors.red,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await NotificationService().openAutoStartSettings();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Open Autostart Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),
            _buildStep(
              '2',
              'Disable Battery Saver',
              'Security app → Battery → Turn OFF',
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildStep(
              '3',
              'Set Battery to "No restrictions"',
              'Settings → Apps → Rowzow → Battery saver → No restrictions',
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildStep(
              '4',
              'Lock App in Recent Apps',
              'Recent apps button → Swipe down on Rowzow → Tap lock icon 🔒',
              Colors.green,
            ),
            const SizedBox(height: 16),
            const Text(
              'After completing ALL steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('• Restart your phone'),
            const Text('• Test with a 1-minute PS4/PS5 session'),
            const Text('• Close app and wait'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Without Autostart enabled, notifications will NEVER work when app is closed!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('I\'ll Do It Later'),
        ),
        ElevatedButton(
          onPressed: () async {
            await NotificationService().openAutoStartSettings();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Open Settings Now'),
        ),
      ],
    );
  }

  Widget _buildStep(String number, String title, String description, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}




