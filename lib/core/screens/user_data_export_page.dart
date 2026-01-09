import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class UserDataExportPage extends StatefulWidget {
  const UserDataExportPage({super.key});

  @override
  State<UserDataExportPage> createState() => _UserDataExportPageState();
}

class _UserDataExportPageState extends State<UserDataExportPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isExporting = false;
  String _statusMessage = '';
  int _totalUsers = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export User Data'),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Export Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This will export all user details including:',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoItem('Customer Name'),
                    _buildInfoItem('Phone Number'),
                    _buildInfoItem('Session Date & Time'),
                    _buildInfoItem('Service Type'),
                    _buildInfoItem('Total Amount'),
                    const SizedBox(height: 12),
                    if (_totalUsers > 0)
                      Text(
                        'Total users found: $_totalUsers',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportUserData,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.file_download),
              label: Text(_isExporting ? 'Exporting...' : 'Export to Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('Error')
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage.contains('Error')
                        ? Colors.red.shade300
                        : Colors.green.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusMessage.contains('Error')
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: _statusMessage.contains('Error')
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains('Error')
                              ? Colors.red.shade900
                              : Colors.green.shade900,
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
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _exportUserData() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Fetching user data...';
      _totalUsers = 0;
    });

    try {
      // Create Excel workbook
      final excel = Excel.createExcel();
      excel.delete('Sheet1'); // Delete default sheet
      final sheet = excel['User Data'];

      // Add headers
      sheet.appendRow([
        TextCellValue('Customer Name'),
        TextCellValue('Phone Number'),
        TextCellValue('Date'),
        TextCellValue('Time'),
        TextCellValue('Service Type'),
        TextCellValue('Duration'),
        TextCellValue('Total Amount'),
        TextCellValue('Status'),
      ]);

      // Style headers
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.lightBlue,
        fontColorHex: ExcelColor.white,
      );
      for (int i = 0; i < 8; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .cellStyle = headerStyle;
      }

      final Set<String> uniqueUsers = {}; // Track unique phone numbers

      // Fetch active sessions
      final activeSessionsSnapshot =
          await _firestore.collection('active_sessions').get();

      for (var sessionDoc in activeSessionsSnapshot.docs) {
        final sessionData = sessionDoc.data();
        final customerName = sessionData['customerName'] as String? ?? 'Unknown';
        final phoneNumber = sessionData['phoneNumber'] as String? ?? '';
        final startTime = sessionData['startTime'] as Timestamp?;
        final totalAmount = (sessionData['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final services = List<Map<String, dynamic>>.from(
          sessionData['services'] ?? [],
        );

        if (phoneNumber.isNotEmpty && phoneNumber != 'NA') {
          uniqueUsers.add(phoneNumber);
        }

        if (startTime != null) {
          final dateTime = startTime.toDate();
          final dateStr = DateFormat('yyyy-MM-dd').format(dateTime);
          final timeStr = DateFormat('HH:mm').format(dateTime);

          if (services.isEmpty) {
            // Session without services
            sheet.appendRow([
              TextCellValue(customerName),
              TextCellValue(phoneNumber.isEmpty ? 'N/A' : phoneNumber),
              TextCellValue(dateStr),
              TextCellValue(timeStr),
              TextCellValue('N/A'),
              TextCellValue('N/A'),
              TextCellValue(totalAmount.toStringAsFixed(2)),
              TextCellValue('Active'),
            ]);
          } else {
            // Add each service as a separate row
            for (var service in services) {
              final serviceType = service['type'] as String? ?? 'N/A';
              final hours = (service['hours'] as num?)?.toInt() ?? 0;
              final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
              final servicePrice = (service['price'] as num?)?.toDouble() ?? 0.0;
              String duration = '';
              if (hours > 0 && minutes > 0) {
                duration = '${hours}h ${minutes}m';
              } else if (hours > 0) {
                duration = '${hours}h';
              } else if (minutes > 0) {
                duration = '${minutes}m';
              } else {
                duration = 'N/A';
              }

              sheet.appendRow([
                TextCellValue(customerName),
                TextCellValue(phoneNumber.isEmpty ? 'N/A' : phoneNumber),
                TextCellValue(dateStr),
                TextCellValue(timeStr),
                TextCellValue(serviceType),
                TextCellValue(duration),
                TextCellValue(servicePrice.toStringAsFixed(2)),
                TextCellValue('Active'),
              ]);
            }
          }
        }
      }

      // Fetch history sessions (closed sessions)
      final now = DateTime.now();
      // Get sessions from last 365 days
      for (int i = 0; i < 365; i++) {
        final date = now.subtract(Duration(days: i));
        final dateId = DateFormat('yyyy-MM-dd').format(date);

        try {
          final historySessionsSnapshot = await _firestore
              .collection('days')
              .doc(dateId)
              .collection('sessions')
              .get();

          for (var sessionDoc in historySessionsSnapshot.docs) {
            final sessionData = sessionDoc.data();
            final customerName = sessionData['customerName'] as String? ?? 'Unknown';
            final phoneNumber = sessionData['phoneNumber'] as String? ?? '';
            final startTime = sessionData['startTime'] as Timestamp?;
            final totalAmount = (sessionData['totalAmount'] as num?)?.toDouble() ?? 0.0;
            final services = List<Map<String, dynamic>>.from(
              sessionData['services'] ?? [],
            );

            if (phoneNumber.isNotEmpty && phoneNumber != 'NA') {
              uniqueUsers.add(phoneNumber);
            }

            if (startTime != null) {
              final dateTime = startTime.toDate();
              final dateStr = DateFormat('yyyy-MM-dd').format(dateTime);
              final timeStr = DateFormat('HH:mm').format(dateTime);

              if (services.isEmpty) {
                // Session without services
                sheet.appendRow([
                  TextCellValue(customerName),
                  TextCellValue(phoneNumber.isEmpty ? 'N/A' : phoneNumber),
                  TextCellValue(dateStr),
                  TextCellValue(timeStr),
                  TextCellValue('N/A'),
                  TextCellValue('N/A'),
                  TextCellValue(totalAmount.toStringAsFixed(2)),
                  TextCellValue('Closed'),
                ]);
              } else {
                // Add each service as a separate row
                for (var service in services) {
                  final serviceType = service['type'] as String? ?? 'N/A';
                  final hours = (service['hours'] as num?)?.toInt() ?? 0;
                  final minutes = (service['minutes'] as num?)?.toInt() ?? 0;
                  final servicePrice = (service['price'] as num?)?.toDouble() ?? 0.0;
                  String duration = '';
                  if (hours > 0 && minutes > 0) {
                    duration = '${hours}h ${minutes}m';
                  } else if (hours > 0) {
                    duration = '${hours}h';
                  } else if (minutes > 0) {
                    duration = '${minutes}m';
                  } else {
                    duration = 'N/A';
                  }

                  sheet.appendRow([
                    TextCellValue(customerName),
                    TextCellValue(phoneNumber.isEmpty ? 'N/A' : phoneNumber),
                    TextCellValue(dateStr),
                    TextCellValue(timeStr),
                    TextCellValue(serviceType),
                    TextCellValue(duration),
                    TextCellValue(servicePrice.toStringAsFixed(2)),
                    TextCellValue('Closed'),
                  ]);
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching history for $dateId: $e');
          // Continue with next date
        }
      }

      // Update total users count
      setState(() {
        _totalUsers = uniqueUsers.length;
      });

      // Save Excel file
      final fileName = 'user_data_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final bytes = excel.save();

      if (bytes == null) {
        throw Exception('Failed to generate Excel file');
      }

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      setState(() {
        _statusMessage = 'Export completed! Found $_totalUsers unique users. File saved.';
      });

      // Share the file
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'User Data Export - $_totalUsers unique users',
        subject: 'Rowzow User Data Export',
      );

      setState(() {
        _isExporting = false;
      });
    } catch (e) {
      setState(() {
        _isExporting = false;
        _statusMessage = 'Error exporting data: ${e.toString()}';
      });
    }
  }
}
