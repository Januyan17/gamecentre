import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:rowzow/core/services/firebase_service.dart';
import 'package:rowzow/core/services/daily_reset_service.dart';
import 'package:rowzow/core/providers/session_provider.dart';
import 'create_session_page.dart';
import 'session_detail_page.dart';
import 'pricing_settings_page.dart';
import 'password_dialog.dart';
import '../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'miui_setup_dialog.dart';
import 'package:intl/intl.dart';

// Helper method to get service color
Color _getServiceColor(String type) {
  switch (type) {
    case 'PS5':
      return Colors.blue;
    case 'PS4':
      return Colors.purple.shade700;
    case 'VR':
      return Colors.purple.shade500;
    case 'Theatre':
      return Colors.red.shade700;
    case 'Simulator':
      return Colors.orange.shade700;
    default:
      return Colors.grey;
  }
}

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
      final prefs = await SharedPreferences.getInstance();
      
      // Check all active sessions, not just the provider's activeSessionId
      final fs = FirebaseService();
      final activeSessionsSnapshot = await fs.activeSessionsRef().get();
      
      if (activeSessionsSnapshot.docs.isEmpty) return;

      final now = DateTime.now();

      for (var sessionDoc in activeSessionsSnapshot.docs) {
        final sessionId = sessionDoc.id;
        final sessionData = sessionDoc.data() as Map<String, dynamic>?;
        if (sessionData == null) continue;

        final services = List<Map<String, dynamic>>.from(sessionData['services'] ?? []);
        final customerName = sessionData['customerName'] as String? ?? 'Customer';

        for (var service in services) {
          final serviceType = service['type'] as String? ?? '';
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
            // Calculate duration based on games (5 minutes per game)
            final games = (service['games'] as num?)?.toInt() ?? 1;
            final duration = games * 5; // 5 minutes per game
            endTime = startTime.add(Duration(minutes: duration));
          } else if (serviceType == 'VR') {
            final startTime = DateTime.parse(startTimeStr);
            // Calculate duration based on games (5 minutes per game)
            final games = (service['games'] as num?)?.toInt() ?? 1;
            final duration = games * 5; // 5 minutes per game
            endTime = startTime.add(Duration(minutes: duration));
          }

          // NOTE: Notifications are now handled by Android Alarm Manager (alarmCallback)
          // The dashboard check is disabled to prevent duplicate notifications
          // The alarm manager is more reliable and handles notifications in background
          // 
          // We still check service times here for other purposes (UI updates, etc.)
          // but we don't show notifications to avoid duplicates with the alarm callback
          if (endTime != null) {
            final timeDiff = now.difference(endTime);
            if (timeDiff.inSeconds >= 0 && timeDiff.inSeconds <= 30) {
              // Service time is up - alarm manager will handle the notification
              // This check can be used for other purposes (UI indicators, etc.)
              final serviceId = service['id'] as String? ?? '';
              debugPrint('ℹ️ Service $serviceType (ID: $serviceId) time is up - notification handled by alarm manager');
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset(
              'assets/rowzow.jpeg',
              height: 40,
              width: 40,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text(
              'RowZow',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
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
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.shade700,
                      Colors.purple.shade500,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Today Total',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.purple.shade100,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rs ${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 50,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Total Users',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.purple.shade100,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$users',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Active Sessions Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.sports_esports,
                        color: Colors.purple.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Active Sessions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.sports_esports,
                                size: 64,
                                color: Colors.purple.shade300,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'No Active Sessions',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create a new session to get started',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 32),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const CreateSessionPage()),
                                );
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create Session'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
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
                        // Properly handle null/undefined discount (when removed, field is deleted)
                        final discountValue = data['discount'];
                        final discount = discountValue != null ? (discountValue as num).toDouble() : 0.0;
                        // finalAmount might be deleted when discount is removed, so default to totalAmount
                        final finalAmountValue = data['finalAmount'];
                        final finalAmount = finalAmountValue != null 
                            ? (finalAmountValue as num).toDouble() 
                            : totalAmount;

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
                          timeInfo = 'Started: ${DateFormat('hh:mm a').format(start)}';
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          key: ValueKey('${doc.id}-${services.length}-${totalAmount}-${discount}-${finalAmount}'),
                          child: ExpansionTile(
                            initiallyExpanded: services.isNotEmpty,
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            childrenPadding: const EdgeInsets.only(bottom: 8),
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.shade700,
                              radius: 24,
                              child: Text(
                                customerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            title: Text(
                              customerName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.purple.shade900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Show total amount with discount if applicable
                                if (discount > 0) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Total: Rs ${totalAmount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          decoration: TextDecoration.lineThrough,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Icon(
                                        Icons.discount,
                                        size: 14,
                                        color: Colors.green.shade700,
                                      ),
                                      Text(
                                        'Rs ${discount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Final: Rs ${finalAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ] else
                                  Text(
                                    'Total: Rs ${totalAmount.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (services.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.list,
                                          size: 14,
                                          color: Colors.purple.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${services.length} service${services.length != 1 ? 's' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.purple.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                if (timeInfo.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      timeInfo,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (services.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${services.length}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.purple.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (services.isNotEmpty) const SizedBox(width: 4),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.open_in_new, size: 16, color: Colors.purple.shade700),
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
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
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    onPressed:
                                        () => _showDeleteConfirmation(
                                          context,
                                          doc.id,
                                          customerName,
                                          totalAmount,
                                        ),
                                    tooltip: 'Delete Session',
                                  ),
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
                                  } else if (service['slots'] != null && service['games'] != null) {
                                    // VR Game with slots
                                    final slots = service['slots'] is int 
                                        ? service['slots'] as int 
                                        : int.tryParse(service['slots'].toString()) ?? 0;
                                    final games = service['games'] is int 
                                        ? service['games'] as int 
                                        : int.tryParse(service['games'].toString()) ?? 0;
                                    subtitle =
                                        '$slots slot${slots != 1 ? 's' : ''} ($games games) - Rs ${price.toStringAsFixed(2)}';
                                  } else if (service['games'] != null && service['type'] == 'Simulator') {
                                    // Simulator with games
                                    final games = service['games'] is int 
                                        ? service['games'] as int 
                                        : int.tryParse(service['games'].toString()) ?? 0;
                                    subtitle =
                                        '$games game${games != 1 ? 's' : ''} - Rs ${price.toStringAsFixed(2)}';
                                  } else if (service['duration'] != null) {
                                    subtitle =
                                        '${service['duration']} min - Rs ${price.toStringAsFixed(2)}';
                                  }

                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _getServiceColor(type).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          type == 'PS5'
                                              ? Icons.sports_esports
                                              : type == 'PS4'
                                              ? Icons.videogame_asset
                                              : type == 'VR'
                                              ? Icons.view_in_ar
                                              : type == 'Theatre'
                                              ? Icons.movie
                                              : Icons.category,
                                          color: _getServiceColor(type),
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        '$type${multiplayer ? ' (Multiplayer)' : ''}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        subtitle,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
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

              // Floating Action Button for New Session
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateSessionPage()),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text(
                      'New Session',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}



