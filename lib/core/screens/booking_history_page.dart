import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key});

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedServiceType;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  Color _getServiceColor(String serviceType) {
    switch (serviceType) {
      case 'PS5':
        return Colors.blue;
      case 'PS4':
        return Colors.purple.shade700;
      case 'VR':
        return Colors.purple.shade500;
      case 'Simulator':
        return Colors.orange.shade700;
      case 'Theatre':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }

  IconData _getServiceIcon(String serviceType) {
    switch (serviceType) {
      case 'PS5':
        return Icons.sports_esports;
      case 'PS4':
        return Icons.videogame_asset;
      case 'VR':
        return Icons.view_in_ar;
      case 'Simulator':
        return Icons.directions_car;
      case 'Theatre':
        return Icons.movie;
      default:
        return Icons.category;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'converted_to_session':
        return Colors.green;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(2020, 1, 1);
    final lastDate = now.add(const Duration(days: 365));

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: _selectedStartDate != null && _selectedEndDate != null
          ? DateTimeRange(start: _selectedStartDate!, end: _selectedEndDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _selectedStartDate = picked.start;
        _selectedEndDate = picked.end;
      });
    }
  }

  Query _buildQuery() {
    // IMPORTANT: Always fetch all data and filter client-side to avoid composite index requirement
    // This way we can order by recordedAt without needing a composite index
    // Filtering by service type and date range will be done client-side
    Query query = _firestore.collection('all_bookings_history')
        .orderBy('recordedAt', descending: true);

    return query;
  }

  bool _matchesDateFilter(String? date) {
    if (date == null || date.isEmpty) return true;
    if (_selectedStartDate == null && _selectedEndDate == null) return true;

    try {
      // Parse the date string (format: yyyy-MM-dd)
      final dateParts = date.split('-');
      if (dateParts.length != 3) {
        debugPrint('Invalid date format: $date');
        return true; // Include if we can't parse
      }

      final bookingDate = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );

      // Compare dates only (ignore time)
      if (_selectedStartDate != null) {
        final startDateOnly = DateTime(
          _selectedStartDate!.year,
          _selectedStartDate!.month,
          _selectedStartDate!.day,
        );
        if (bookingDate.isBefore(startDateOnly)) {
          return false;
        }
      }

      if (_selectedEndDate != null) {
        final endDateOnly = DateTime(
          _selectedEndDate!.year,
          _selectedEndDate!.month,
          _selectedEndDate!.day,
        );
        if (bookingDate.isAfter(endDateOnly)) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return true; // Include if we can't parse
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Booking History'),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                // Service Type Filter
                DropdownButtonFormField<String>(
                  value: _selectedServiceType,
                  decoration: const InputDecoration(
                    labelText: 'Service Type',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All Services'),
                    ),
                    ...['PS5', 'PS4', 'VR', 'Simulator', 'Theatre'].map((type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedServiceType = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // Date Range Filter
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectDateRange,
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          _selectedStartDate != null && _selectedEndDate != null
                              ? '${DateFormat('MMM dd').format(_selectedStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_selectedEndDate!)}'
                              : 'Select Date Range',
                        ),
                      ),
                    ),
                    if (_selectedStartDate != null || _selectedEndDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _selectedStartDate = null;
                            _selectedEndDate = null;
                          });
                        },
                        tooltip: 'Clear Date Filter',
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Bookings List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final errorMsg = snapshot.error.toString();
                  final needsIndex = errorMsg.contains('index') || errorMsg.contains('requires an index');
                  
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text(
                            needsIndex 
                                ? 'Composite Index Required'
                                : 'Error loading booking history',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 12),
                          if (needsIndex) ...[
                            Text(
                              'Firestore requires a composite index for filtering by service type and ordering by recordedAt.',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Please create the index in Firebase Console or click the link in the error message.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              textAlign: TextAlign.center,
                            ),
                          ] else ...[
                            Text(
                              errorMsg,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => setState(() {}),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No booking history found',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                final allBookings = snapshot.data!.docs;
                
                // Filter by service type and date range on client side
                // This avoids the need for a composite index in Firestore
                List<QueryDocumentSnapshot> filteredBookings = allBookings.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  
                  // Filter by service type if selected
                  if (_selectedServiceType != null) {
                    final serviceType = data['serviceType'] as String? ?? '';
                    if (serviceType != _selectedServiceType) {
                      return false;
                    }
                  }
                  
                  // Filter by date range if selected
                  if (_selectedStartDate != null || _selectedEndDate != null) {
                    final date = data['date'] as String?;
                    if (!_matchesDateFilter(date)) {
                      return false;
                    }
                  }
                  
                  return true;
                }).toList();
                
                debugPrint('Filtered bookings: ${filteredBookings.length} out of ${allBookings.length} total');

                // Sort by recordedAt if available, otherwise by date
                // (Data is already sorted by Firestore, but we re-sort after filtering)
                filteredBookings.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  
                  final recordedAtA = dataA['recordedAt'] as Timestamp?;
                  final recordedAtB = dataB['recordedAt'] as Timestamp?;
                  
                  if (recordedAtA != null && recordedAtB != null) {
                    return recordedAtB.compareTo(recordedAtA); // Descending
                  }
                  
                  // Fallback to date comparison
                  final dateA = dataA['date'] as String? ?? '';
                  final dateB = dataB['date'] as String? ?? '';
                  return dateB.compareTo(dateA); // Descending
                });

                final bookings = filteredBookings;

                if (bookings.isEmpty) {
                  return const Center(
                    child: Text(
                      'No booking history found for selected filters',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookings.length,
                  itemBuilder: (context, index) {
                    final doc = bookings[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final serviceType = data['serviceType'] as String? ?? 'Unknown';
                    final customerName = data['customerName'] as String? ?? 'N/A';
                    final phoneNumber = data['phoneNumber'] as String? ?? '';
                    final date = data['date'] as String? ?? '';
                    final timeSlot = data['timeSlot'] as String? ?? '';
                    final status = data['status'] as String? ?? 'pending';
                    final durationHours = (data['durationHours'] as num?)?.toDouble() ?? 0.0;
                    final recordedAt = data['recordedAt'] as Timestamp?;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _getServiceColor(serviceType).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getServiceIcon(serviceType),
                                    color: _getServiceColor(serviceType),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        serviceType,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: _getServiceColor(serviceType),
                                        ),
                                      ),
                                      Text(
                                        customerName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(status).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _getStatusColor(status),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Details
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  date.isNotEmpty
                                      ? DateFormat('MMM dd, yyyy').format(DateTime.parse('${date}T00:00:00'))
                                      : 'Date not available',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  timeSlot.isNotEmpty ? _formatTime12Hour(timeSlot) : 'Time not available',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.timer, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  '${durationHours.toStringAsFixed(1)}h',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                            if (phoneNumber.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.phone, size: 16, color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Text(
                                    phoneNumber,
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.call, size: 18),
                                    color: Colors.green,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      final uri = Uri.parse('tel:$phoneNumber');
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      }
                                    },
                                    tooltip: 'Call',
                                  ),
                                ],
                              ),
                            ],
                            // Service-specific details
                            if (serviceType == 'PS5' || serviceType == 'PS4') ...[
                              const SizedBox(height: 8),
                              Text(
                                'Consoles: ${data['consoleCount'] ?? 1}',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                            if (serviceType == 'Theatre') ...[
                              const SizedBox(height: 8),
                              Text(
                                'Hours: ${data['hours'] ?? 1} | People: ${data['totalPeople'] ?? 1}',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                            if (serviceType == 'VR' || serviceType == 'Simulator') ...[
                              const SizedBox(height: 8),
                              Text(
                                'Duration: ${data['durationMinutes'] ?? 0} minutes',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                            // Recorded timestamp
                            if (recordedAt != null) ...[
                              const SizedBox(height: 8),
                              Divider(color: Colors.grey.shade300),
                              Text(
                                'Recorded: ${DateFormat('MMM dd, yyyy hh:mm a').format(recordedAt.toDate())}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime12Hour(String time24Hour) {
    try {
      final parts = time24Hour.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final period = hour >= 12 ? 'PM' : 'AM';
        final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
      }
    } catch (e) {
      debugPrint('Error formatting time: $e');
    }
    return time24Hour;
  }
}
