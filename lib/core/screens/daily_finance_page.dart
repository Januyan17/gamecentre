import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DailyFinancePage extends StatefulWidget {
  const DailyFinancePage({super.key});

  @override
  State<DailyFinancePage> createState() => _DailyFinancePageState();
}

class _DailyFinancePageState extends State<DailyFinancePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _expenseController = TextEditingController();
  final TextEditingController _expenseNoteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  DateTime _selectedDate = DateTime.now();
  double _dailyIncome = 0.0;
  double _totalExpenses = 0.0;
  List<Map<String, dynamic>> _expenses = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isSaved = false;
  bool _autoPreserved = false;
  Timestamp? _savedAt;
  Timestamp? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadDailyData();
  }

  @override
  void dispose() {
    _expenseController.dispose();
    _expenseNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadDailyData() async {
    setState(() => _isLoading = true);
    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
      
      // Calculate income from all closed sessions for this date (from history)
      await _calculateIncomeFromSessions(dateId);
      
      // Also check day's total as backup (for backward compatibility)
      final dayDoc = await _firestore.collection('days').doc(dateId).get();
      if (dayDoc.exists) {
        final data = dayDoc.data();
        final dayTotal = (data?['totalAmount'] ?? 0).toDouble();
        // Use the higher value (in case sessions were added after finance was saved)
        if (dayTotal > _dailyIncome) {
          _dailyIncome = dayTotal;
        }
      }

      // Load expenses and saved finance record
      final financeDoc = await _firestore.collection('daily_finance').doc(dateId).get();
      if (financeDoc.exists) {
        final data = financeDoc.data();
        if (data != null) {
          // If this is an auto-preserved record, update income from current sessions
          final autoPreserved = data['autoPreserved'] ?? false;
          if (autoPreserved && _dailyIncome > 0) {
            // Update income in case new sessions were closed
            final existingIncome = (data['income'] ?? 0).toDouble();
            if (_dailyIncome > existingIncome) {
              // Income has increased, update it
              await _firestore.collection('daily_finance').doc(dateId).update({
                'income': _dailyIncome,
                'netProfit': _dailyIncome - (data['totalExpenses'] ?? 0).toDouble(),
              });
            }
          }
          final expensesList = data['expenses'];
          _expenses = [];
          
          if (expensesList != null && expensesList is List) {
            for (var expense in expensesList) {
              if (expense is Map) {
                final expenseMap = Map<String, dynamic>.from(expense);
                // Ensure timestamp is properly converted from Firestore
                if (expenseMap['timestamp'] != null) {
                  if (expenseMap['timestamp'] is Timestamp) {
                    // Already a Timestamp, keep it
                  } else if (expenseMap['timestamp'] is Map) {
                    // Convert Firestore Timestamp map to Timestamp object
                    try {
                      final tsMap = expenseMap['timestamp'] as Map;
                      if (tsMap.containsKey('_seconds')) {
                        expenseMap['timestamp'] = Timestamp(
                          tsMap['_seconds'] as int,
                          (tsMap['_nanoseconds'] ?? 0) as int,
                        );
                      } else {
                        expenseMap['timestamp'] = Timestamp.fromDate(DateTime.now());
                      }
                    } catch (e) {
                      expenseMap['timestamp'] = Timestamp.fromDate(DateTime.now());
                    }
                  } else {
                    // Convert to Timestamp if it's something else
                    expenseMap['timestamp'] = Timestamp.fromDate(DateTime.now());
                  }
                } else {
                  expenseMap['timestamp'] = Timestamp.fromDate(DateTime.now());
                }
                _expenses.add(expenseMap);
              }
            }
          }
          
          _totalExpenses = _expenses.fold<double>(
            0.0,
            (sum, expense) => sum + (expense['amount'] as num).toDouble(),
          );
          _isSaved = data['isSaved'] ?? false;
          _autoPreserved = data['autoPreserved'] ?? false;
          
          // Load saved/updated timestamps if available
          if (data['savedAt'] != null) {
            if (data['savedAt'] is Timestamp) {
              _savedAt = data['savedAt'] as Timestamp;
            } else if (data['savedAt'] is Map) {
              final tsMap = data['savedAt'] as Map;
              if (tsMap.containsKey('_seconds')) {
                _savedAt = Timestamp(tsMap['_seconds'] as int, (tsMap['_nanoseconds'] ?? 0) as int);
              }
            }
          }
          if (data['updatedAt'] != null) {
            if (data['updatedAt'] is Timestamp) {
              _updatedAt = data['updatedAt'] as Timestamp;
            } else if (data['updatedAt'] is Map) {
              final tsMap = data['updatedAt'] as Map;
              if (tsMap.containsKey('_seconds')) {
                _updatedAt = Timestamp(tsMap['_seconds'] as int, (tsMap['_nanoseconds'] ?? 0) as int);
              }
            }
          }
        } else {
          _expenses = [];
          _totalExpenses = 0.0;
          _isSaved = false;
        }
      } else {
        _expenses = [];
        _totalExpenses = 0.0;
        _isSaved = false;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Calculate income from all closed sessions for the selected date
  Future<void> _calculateIncomeFromSessions(String dateId) async {
    try {
      double totalIncome = 0.0;
      
      // Get all closed sessions from history for this date
      final sessionsSnapshot = await _firestore
          .collection('days')
          .doc(dateId)
          .collection('sessions')
          .get();
      
      for (var doc in sessionsSnapshot.docs) {
        final sessionData = doc.data();
        // Use finalAmount if available (includes discount), otherwise totalAmount
        final amount = (sessionData['finalAmount'] ?? 
                       sessionData['totalAmount'] ?? 
                       0).toDouble();
        totalIncome += amount;
      }
      
      setState(() {
        _dailyIncome = totalIncome;
      });
    } catch (e) {
      print('Error calculating income from sessions: $e');
      // Keep existing income if calculation fails
    }
  }

  /// Refresh income calculation (useful when new sessions are closed)
  Future<void> _refreshIncome() async {
    final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
    await _calculateIncomeFromSessions(dateId);
    
    // Also check day's total
    final dayDoc = await _firestore.collection('days').doc(dateId).get();
    if (dayDoc.exists) {
      final data = dayDoc.data();
      final dayTotal = (data?['totalAmount'] ?? 0).toDouble();
      if (dayTotal > _dailyIncome) {
        setState(() {
          _dailyIncome = dayTotal;
        });
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Income refreshed successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatExpenseTimestamp(dynamic timestamp) {
    try {
      if (timestamp == null) {
        return DateFormat('hh:mm a').format(DateTime.now());
      }
      if (timestamp is Timestamp) {
        return DateFormat('hh:mm a').format(timestamp.toDate());
      }
      if (timestamp is DateTime) {
        return DateFormat('hh:mm a').format(timestamp);
      }
      return DateFormat('hh:mm a').format(DateTime.now());
    } catch (e) {
      return DateFormat('hh:mm a').format(DateTime.now());
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadDailyData();
    }
  }

  void _addExpense() {
    if (_formKey.currentState!.validate()) {
      final amount = double.parse(_expenseController.text);
      final note = _expenseNoteController.text.trim();
      
      setState(() {
        _expenses.add({
          'amount': amount,
          'note': note.isEmpty ? 'Expense' : note,
          'timestamp': Timestamp.fromDate(DateTime.now()),
        });
        _totalExpenses += amount;
        _expenseController.clear();
        _expenseNoteController.clear();
      });
    }
  }

  Future<void> _removeExpense(int index) async {
    if (index < 0 || index >= _expenses.length) return;

    final removedAmount = (_expenses[index]['amount'] as num).toDouble();
    
    setState(() {
      _totalExpenses -= removedAmount;
      _expenses.removeAt(index);
    });

    // If finance is already saved, update the database immediately
    if (_isSaved) {
      try {
        final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
        final netProfit = _dailyIncome - _totalExpenses;

        // Convert expenses to Firestore format
        final expensesForFirestore = _expenses.map((expense) {
          final expenseMap = Map<String, dynamic>.from(expense);
          if (expenseMap['timestamp'] is Timestamp) {
            expenseMap['timestamp'] = expenseMap['timestamp'];
          } else if (expenseMap['timestamp'] is DateTime) {
            expenseMap['timestamp'] = Timestamp.fromDate(expenseMap['timestamp'] as DateTime);
          }
          return expenseMap;
        }).toList();

        // Get existing savedAt to preserve it
        final existingDoc = await _firestore.collection('daily_finance').doc(dateId).get();
        final existingData = existingDoc.data();
        dynamic savedAt = FieldValue.serverTimestamp();
        if (existingData != null && existingData['savedAt'] != null) {
          savedAt = existingData['savedAt'];
        }

        // Update the database immediately
        await _firestore.collection('daily_finance').doc(dateId).update({
          'expenses': expensesForFirestore,
          'totalExpenses': _totalExpenses,
          'netProfit': netProfit,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update local updatedAt timestamp
        final updatedDoc = await _firestore.collection('daily_finance').doc(dateId).get();
        if (updatedDoc.exists) {
          final updatedData = updatedDoc.data();
          if (updatedData != null && updatedData['updatedAt'] != null) {
            if (updatedData['updatedAt'] is Timestamp) {
              _updatedAt = updatedData['updatedAt'] as Timestamp;
            }
          }
        }

        if (mounted) {
          setState(() {}); // Refresh UI to show updated timestamp
        }
      } catch (e) {
        // If update fails, show error but keep the local deletion
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating database: $e'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveFinance() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Finance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Income:'),
                Text(
                  'Rs ${_dailyIncome.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Expenses:'),
                Text(
                  'Rs ${_totalExpenses.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Net Profit:'),
                Text(
                  'Rs ${(_dailyIncome - _totalExpenses).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (_dailyIncome - _totalExpenses) >= 0 ? Colors.blue : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isSaved)
              const Text(
                '⚠ This will update the existing finance record for this date.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              )
            else
              const Text(
                'Are you sure you want to save this finance data?',
                style: TextStyle(fontSize: 14),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(_isSaved ? 'Update' : 'Save'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return; // User cancelled
    }

    setState(() => _isSaving = true);
    try {
      final dateId = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final netProfit = _dailyIncome - _totalExpenses;

      // Convert expenses to Firestore format (ensure timestamps are proper)
      final expensesForFirestore = _expenses.map((expense) {
        final expenseMap = Map<String, dynamic>.from(expense);
        // Ensure timestamp is properly formatted
        if (expenseMap['timestamp'] is Timestamp) {
          expenseMap['timestamp'] = expenseMap['timestamp'];
        } else if (expenseMap['timestamp'] is DateTime) {
          expenseMap['timestamp'] = Timestamp.fromDate(expenseMap['timestamp'] as DateTime);
        }
        return expenseMap;
      }).toList();

      // Get existing savedAt if updating (preserve original save time)
      final existingDoc = await _firestore.collection('daily_finance').doc(dateId).get();
      final existingData = existingDoc.data();
      dynamic savedAt = FieldValue.serverTimestamp();
      if (existingData != null && existingData['savedAt'] != null) {
        savedAt = existingData['savedAt']; // Preserve existing savedAt
      }
      
      // Save finance data with date as document ID (ensures one record per date)
      await _firestore.collection('daily_finance').doc(dateId).set({
        'date': dateId,
        'dateTimestamp': Timestamp.fromDate(DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        )),
        'income': _dailyIncome,
        'expenses': expensesForFirestore,
        'totalExpenses': _totalExpenses,
        'netProfit': netProfit,
        'isSaved': true,
        'savedAt': savedAt, // Preserve original save time
        'updatedAt': FieldValue.serverTimestamp(), // Always update this
      }, SetOptions(merge: true));

      // Update local timestamps
      final updatedDoc = await _firestore.collection('daily_finance').doc(dateId).get();
      if (updatedDoc.exists) {
        final updatedData = updatedDoc.data();
        if (updatedData != null) {
          if (updatedData['savedAt'] != null) {
            if (updatedData['savedAt'] is Timestamp) {
              _savedAt = updatedData['savedAt'] as Timestamp;
            }
          }
          if (updatedData['updatedAt'] != null) {
            if (updatedData['updatedAt'] is Timestamp) {
              _updatedAt = updatedData['updatedAt'] as Timestamp;
            }
          }
        }
      }
      
      setState(() => _isSaved = true);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isSaved ? 'Finance data updated successfully' : 'Finance data saved successfully',
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
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving finance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final netProfit = _dailyIncome - _totalExpenses;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Finance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshIncome,
            tooltip: 'Refresh Income',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
            tooltip: 'Select Date',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date selector
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _pickDate,
                                  icon: const Icon(Icons.edit_calendar),
                                  label: const Text('Change'),
                                ),
                              ],
                            ),
                            if (_autoPreserved && !_isSaved)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade700),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Auto-preserved: Income saved automatically',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary Card - Total Income and Expenses
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade50,
                              Colors.purple.shade50,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Text(
                              'Daily Summary',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                // Total Income
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.green.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Icon(
                                          Icons.arrow_upward,
                                          color: Colors.green,
                                          size: 32,
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Total Income',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Rs ${_dailyIncome.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Total Expenses
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.shade300,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Icon(
                                          Icons.arrow_downward,
                                          color: Colors.red,
                                          size: 32,
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Total Expenses',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Rs ${_totalExpenses.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Net Profit
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: netProfit >= 0 
                                    ? Colors.blue.shade100 
                                    : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: netProfit >= 0 
                                      ? Colors.blue.shade300 
                                      : Colors.orange.shade300,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    netProfit >= 0 
                                        ? Icons.trending_up 
                                        : Icons.trending_down,
                                    color: netProfit >= 0 
                                        ? Colors.blue 
                                        : Colors.orange,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Net Profit: ',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    'Rs ${netProfit.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: netProfit >= 0 
                                          ? Colors.blue 
                                          : Colors.orange,
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

                    // Income Card
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily Income (From App)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Rs ${_dailyIncome.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Add Expense Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add Expense',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _expenseController,
                              decoration: const InputDecoration(
                                labelText: 'Expense Amount (Rs)',
                                border: OutlineInputBorder(),
                                prefixText: 'Rs ',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter amount';
                                }
                                final amount = double.tryParse(value);
                                if (amount == null || amount <= 0) {
                                  return 'Please enter valid amount';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _expenseNoteController,
                              decoration: const InputDecoration(
                                labelText: 'Expense Note (Optional)',
                                border: OutlineInputBorder(),
                                hintText: 'e.g., Electricity, Rent, Supplies',
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _addExpense,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Expense'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Expenses List
                    if (_expenses.isNotEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Expenses List',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(_expenses.length, (index) {
                                final expense = _expenses[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(expense['note'] ?? 'Expense'),
                                    subtitle: Text(
                                      _formatExpenseTimestamp(expense['timestamp']),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Rs ${(expense['amount'] as num).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => _removeExpense(index),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Total Expenses Card
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Expenses',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Rs ${_totalExpenses.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Net Profit Card
                    Card(
                      color: netProfit >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Net Profit',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Rs ${netProfit.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: netProfit >= 0 ? Colors.blue : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveFinance,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSaved ? 'Update Finance' : 'Save Finance'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: _isSaved ? Colors.orange : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (_isSaved) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          children: [
                            if (_savedAt != null)
                              Text(
                                '✓ Saved: ${DateFormat('MMM dd, yyyy hh:mm a').format(_savedAt!.toDate())}',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (_updatedAt != null && _savedAt != null && 
                                _updatedAt!.toDate().difference(_savedAt!.toDate()).inSeconds > 5)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '↻ Updated: ${DateFormat('MMM dd, yyyy hh:mm a').format(_updatedAt!.toDate())}',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

