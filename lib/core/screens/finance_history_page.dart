import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class FinanceHistoryPage extends StatelessWidget {
  const FinanceHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('daily_finance')
            .orderBy('dateTimestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No finance records found',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final date = (data['dateTimestamp'] as Timestamp?)?.toDate() ??
                  DateTime.parse(data['date'] ?? '');
              final income = (data['income'] ?? 0).toDouble();
              final totalAdditionalIncome = (data['totalAdditionalIncome'] ?? 0).toDouble();
              final totalIncome = income + totalAdditionalIncome;
              final totalExpenses = (data['totalExpenses'] ?? 0).toDouble();
              final netProfit = (data['netProfit'] ?? 0).toDouble();
              final expenses = List<Map<String, dynamic>>.from(data['expenses'] ?? []);
              final additionalIncome = List<Map<String, dynamic>>.from(data['additionalIncome'] ?? []);
              final isSaved = data['isSaved'] ?? false;
              final autoPreserved = data['autoPreserved'] ?? false;
              
              // Get timestamps
              Timestamp? savedAt;
              Timestamp? updatedAt;
              if (data['savedAt'] != null) {
                if (data['savedAt'] is Timestamp) {
                  savedAt = data['savedAt'] as Timestamp;
                } else if (data['savedAt'] is Map) {
                  final tsMap = data['savedAt'] as Map;
                  if (tsMap.containsKey('_seconds')) {
                    savedAt = Timestamp(tsMap['_seconds'] as int, (tsMap['_nanoseconds'] ?? 0) as int);
                  }
                }
              }
              if (data['updatedAt'] != null) {
                if (data['updatedAt'] is Timestamp) {
                  updatedAt = data['updatedAt'] as Timestamp;
                } else if (data['updatedAt'] is Map) {
                  final tsMap = data['updatedAt'] as Map;
                  if (tsMap.containsKey('_seconds')) {
                    updatedAt = Timestamp(tsMap['_seconds'] as int, (tsMap['_nanoseconds'] ?? 0) as int);
                  }
                }
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                elevation: 2,
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: netProfit >= 0 ? Colors.green : Colors.red,
                    child: Icon(
                      netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    DateFormat('MMM dd, yyyy').format(date),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Income: Rs ${totalIncome.toStringAsFixed(2)}'),
                      Text('Expenses: Rs ${totalExpenses.toStringAsFixed(2)}'),
                      Text(
                        'Net Profit: Rs ${netProfit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: netProfit >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                      if (savedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Saved: ${DateFormat('MMM dd, yyyy hh:mm a').format(savedAt.toDate())}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (updatedAt != null && savedAt != null && 
                          updatedAt.toDate().difference(savedAt.toDate()).inSeconds > 5) ...[
                        Text(
                          'Updated: ${DateFormat('MMM dd, yyyy hh:mm a').format(updatedAt.toDate())}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: autoPreserved
                      ? Tooltip(
                          message: 'Auto-preserved (income saved automatically)',
                          child: const Icon(Icons.auto_awesome, color: Colors.blue),
                        )
                      : isSaved
                          ? Tooltip(
                              message: 'Manually saved',
                              child: const Icon(Icons.check_circle, color: Colors.green),
                            )
                          : Tooltip(
                              message: 'Not saved yet',
                              child: const Icon(Icons.pending, color: Colors.orange),
                            ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Income Detail
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Income (From App):',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Rs ${income.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                if (totalAdditionalIncome > 0) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Additional Income:',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Rs ${totalAdditionalIncome.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Total Income:',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Rs ${totalIncome.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Additional Income Detail
                          if (additionalIncome.isNotEmpty) ...[
                            const Text(
                              'Additional Income:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...additionalIncome.map((incomeItem) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                color: Colors.green.shade50,
                                child: ListTile(
                                  dense: true,
                                  title: Text(incomeItem['note'] ?? 'Additional Income'),
                                  trailing: Text(
                                    'Rs ${(incomeItem['amount'] as num).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                            const SizedBox(height: 12),
                          ],

                          // Expenses Detail
                          if (expenses.isNotEmpty) ...[
                            const Text(
                              'Expenses:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...expenses.map((expense) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  dense: true,
                                  title: Text(expense['note'] ?? 'Expense'),
                                  trailing: Text(
                                    'Rs ${(expense['amount'] as num).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                            const SizedBox(height: 8),
                          ],

                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Expenses:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Rs ${totalExpenses.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Net Profit
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: netProfit >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Net Profit:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Rs ${netProfit.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: netProfit >= 0 ? Colors.blue : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

