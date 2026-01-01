import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:rowzow/core/screens/history_page.dart';
import 'package:rowzow/core/services/firebase_service.dart';
import 'package:rowzow/core/services/daily_reset_service.dart';
import 'package:rowzow/core/providers/session_provider.dart';
import 'create_session_page.dart';
import 'session_detail_page.dart';
import 'pricing_settings_page.dart';
import 'password_dialog.dart';
import 'daily_finance_page.dart';
import 'finance_history_page.dart';
import '../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'miui_setup_dialog.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DailyResetService _dailyResetService = DailyResetService();
  bool _hasCheckedReset = false;

  @override
  void initState() {
    super.initState();
    _performDailyReset();
    _startNotificationChecker();
    _showMiuiSetupDialogIfNeeded();
  }

  /// Show MIUI setup dialog on first launch
  Future<void> _showMiuiSetupDialogIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownDialog = prefs.getBool('miui_setup_shown') ?? false;

    if (!hasShownDialog && mounted) {
      // Wait a bit for the UI to settle
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const MiuiSetupDialog(),
        );

        await prefs.setBool('miui_setup_shown', true);
      }
    }
  }

  /// Start a periodic check for service time completion
  /// This is a workaround for Android's exact alarm restrictions
  void _startNotificationChecker() {
    // Check every 30 seconds if any services have completed
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _checkServiceTimes();
        _startNotificationChecker(); // Schedule next check
      }
    });
  }

  /// Check if any active services have completed and show notifications
  Future<void> _checkServiceTimes() async {
    try {
      final provider = context.read<SessionProvider>();
      if (provider.activeSessionId == null) return;

      final sessionDoc = await provider.sessionsRef().doc(provider.activeSessionId!).get();
      if (!sessionDoc.exists) return;

      final sessionData = sessionDoc.data() as Map<String, dynamic>?;
      if (sessionData == null) return;

      final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);
      final customerName = sessionData['customerName'] as String? ?? 'Customer';
      final now = DateTime.now();

      for (var service in services) {
        final serviceType = service['type'] as String? ?? '';
        if (serviceType == 'VR') continue;

        final startTimeStr = service['startTime'] as String?;
        if (startTimeStr == null) continue;

        DateTime? endTime;
        if (serviceType == 'PS4' || serviceType == 'PS5') {
          final startTime = DateTime.parse(startTimeStr);
          final hours = (service['hours'] as num?)?.toInt() ?? 0;
          final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
          endTime = startTime.add(Duration(hours: hours, minutes: minutes));
        } else if (serviceType == 'Theatre') {
          final startTime = DateTime.parse(startTimeStr);
          final hours = (service['hours'] as num?)?.toInt() ?? 1;
          endTime = startTime.add(Duration(hours: hours));
        } else if (serviceType == 'Simulator') {
          final startTime = DateTime.parse(startTimeStr);
          final duration = (service['duration'] as num?)?.toInt() ?? 30;
          endTime = startTime.add(Duration(minutes: duration));
        }

        // Check if time is up (within last 30 seconds to avoid duplicate notifications)
        if (endTime != null) {
          final timeDiff = now.difference(endTime);
          if (timeDiff.inSeconds >= 0 && timeDiff.inSeconds <= 30) {
            // Time is up! Show notification immediately
            final serviceId = service['id'] as String? ?? '';
            final notificationKey = 'time_up_${serviceId}';

            // Check if we've already notified for this service
            final prefs = await SharedPreferences.getInstance();
            final alreadyNotified = prefs.getBool(notificationKey) ?? false;
            if (!alreadyNotified) {
              // Show immediate notification
              await NotificationService().showImmediateNotification(
                title: 'Time Up: $serviceType',
                body: '$serviceType session for $customerName has completed',
              );

              // Mark as notified
              await prefs.setBool(notificationKey, true);

              debugPrint('🔔 Time-up notification shown for $serviceType');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking service times: $e');
    }
  }

  Future<void> _performDailyReset() async {
    if (!_hasCheckedReset) {
      _hasCheckedReset = true;
      // Perform daily reset check in background
      await _dailyResetService.checkAndPerformDailyReset();

      // Reset provider state after daily reset
      if (mounted) {
        context.read<SessionProvider>().resetState();
      }
    }
  }

  void _showPasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => PasswordDialog(
            onSuccess: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PricingSettingsPage()),
              );
            },
          ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    String sessionId,
    String customerName,
    double totalAmount,
  ) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete Session'),
            content: Text(
              'Are you sure you want to delete this session?\n\n'
              'Customer: $customerName\n'
              'Total Amount: Rs ${totalAmount.toStringAsFixed(2)}\n\n'
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

                  // Store the navigator and scaffold messenger before async operations
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
                    await context.read<SessionProvider>().deleteActiveSession(sessionId);

                    // Wait a bit to ensure Firestore updates
                    await Future.delayed(const Duration(milliseconds: 500));

                    // Close loading dialog using root navigator
                    if (navigator.canPop()) {
                      navigator.pop();
                    }

                    // Wait a bit more to ensure dialog is fully closed
                    await Future.delayed(const Duration(milliseconds: 200));

                    // Show success message using stored scaffold messenger
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  } catch (e) {
                    // Close loading dialog using root navigator
                    if (navigator.canPop()) {
                      navigator.pop();
                    }

                    // Wait a bit to ensure dialog is fully closed
                    await Future.delayed(const Duration(milliseconds: 200));

                    // Show error message using stored scaffold messenger
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RowZow Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showPasswordDialog(context),
            tooltip: 'Pricing Settings',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: fs.dayRef().snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;

          final total = data?['totalAmount'] ?? 0;
          final users = data?['totalUsers'] ?? 0;

          return Column(
            children: [
              // Stats Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      'Today Total: Rs $total',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Total Users: $users', style: const TextStyle(fontSize: 18)),
                  ],
                ),
              ),

              // Active Sessions List
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Active Sessions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: fs.activeSessionsRef().snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sports_esports, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No active sessions',
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final doc = snapshot.data!.docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final customerName = data['customerName'] ?? 'Unknown';
                        final totalAmount = (data['totalAmount'] ?? 0).toDouble();

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

                        final startTime = data['startTime'] as Timestamp?;

                        String timeInfo = '';
                        if (startTime != null) {
                          final start = DateTime.fromMillisecondsSinceEpoch(
                            startTime.seconds * 1000,
                          );
                          timeInfo = 'Started: ${start.toString().substring(11, 16)}';
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          key: ValueKey('${doc.id}-${services.length}-${totalAmount}'),
                          child: ExpansionTile(
                            initiallyExpanded: services.isNotEmpty,
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Text(
                                customerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              customerName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total: Rs ${totalAmount.toStringAsFixed(2)}'),
                                if (services.isNotEmpty)
                                  Text(
                                    '${services.length} service${services.length != 1 ? 's' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (timeInfo.isNotEmpty)
                                  Text(
                                    timeInfo,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (services.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${services.length}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  onPressed: () async {
                                    // Load the session first
                                    await context.read<SessionProvider>().loadSession(doc.id);
                                    // Navigate to session detail
                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const SessionDetailPage(),
                                        ),
                                      );
                                    }
                                  },
                                  tooltip: 'View Details',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed:
                                      () => _showDeleteConfirmation(
                                        context,
                                        doc.id,
                                        customerName,
                                        totalAmount,
                                      ),
                                  tooltip: 'Delete Session',
                                ),
                              ],
                            ),
                            children: [
                              if (services.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'No services added yet',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              else
                                ...services.map((service) {
                                  final type = service['type'] ?? 'Unknown';
                                  final price = (service['price'] ?? 0).toDouble();
                                  final multiplayer = service['multiplayer'] ?? false;
                                  String subtitle = 'Rs ${price.toStringAsFixed(2)}';

                                  if (service['hours'] != null && service['minutes'] != null) {
                                    subtitle =
                                        '${service['hours']}h ${service['minutes']}m${multiplayer ? ' (Multiplayer)' : ''} - Rs ${price.toStringAsFixed(2)}';
                                  } else if (service['duration'] != null) {
                                    subtitle =
                                        '${service['duration']} min - Rs ${price.toStringAsFixed(2)}';
                                  }

                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      type == 'PS5'
                                          ? Icons.sports_esports
                                          : type == 'PS4'
                                          ? Icons.videogame_asset
                                          : Icons.category,
                                      color:
                                          type == 'PS5'
                                              ? Colors.blue
                                              : type == 'PS4'
                                              ? Colors.purple
                                              : Colors.grey,
                                    ),
                                    title: Text('$type${multiplayer ? ' (Multiplayer)' : ''}'),
                                    subtitle: Text(subtitle),
                                  );
                                }).toList(),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CreateSessionPage()),
                              );
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('New Session'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const HistoryPage()),
                              );
                            },
                            icon: const Icon(Icons.history),
                            label: const Text('History'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const DailyFinancePage()),
                              );
                            },
                            icon: const Icon(Icons.account_balance_wallet),
                            label: const Text('Daily Finance'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const FinanceHistoryPage()),
                              );
                            },
                            icon: const Icon(Icons.timeline),
                            label: const Text('Finance History'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
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
    );
  }
}
