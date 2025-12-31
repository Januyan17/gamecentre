import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:rowzow/core/screens/history_page.dart';
import 'package:rowzow/core/services/firebase_service.dart';
import 'package:rowzow/core/providers/session_provider.dart';
import 'create_session_page.dart';
import 'session_detail_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('Gaming Center Dashboard')),
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
                          services = servicesList.map((s) {
                            if (s is Map) {
                              return Map<String, dynamic>.from(s);
                            }
                            return <String, dynamic>{};
                          }).toList().cast<Map<String, dynamic>>();
                        }
                        
                        final startTime = data['startTime'] as Timestamp?;

                        String timeInfo = '';
                        if (startTime != null) {
                          final start = DateTime.fromMillisecondsSinceEpoch(startTime.seconds * 1000);
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
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  onPressed: () async {
                                    // Load the session first
                                    await context.read<SessionProvider>().loadSession(doc.id);
                                    // Navigate to session detail
                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const SessionDetailPage()),
                                      );
                                    }
                                  },
                                  tooltip: 'View Details',
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
                                      color: type == 'PS5'
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
                child: Row(
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
              ),
            ],
          );
        },
      ),
    );
  }
}
