import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class SessionService {
  final FirebaseService _fs = FirebaseService();
  final _uuid = const Uuid();

  Future<String> createSession(String name, {String? phoneNumber}) async {
    final id = _uuid.v4();
    await _fs.activeSessionsRef().doc(id).set({
      'sessionId': id,
      'customerName': name,
      if (phoneNumber != null && phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
      'startTime': Timestamp.now(),
      'status': 'active',
      'services': [],
      'totalAmount': 0,
    });
    return id;
  }

  /// Search for user history by phone number
  /// Returns the most recent session data for the given phone number
  Future<Map<String, dynamic>?> searchUserHistoryByPhone(String phoneNumber) async {
    try {
      // Clean phone number (remove any non-digits)
      final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanPhone.isEmpty) {
        return null;
      }

      final List<Map<String, dynamic>> foundSessions = [];

      // First, check active sessions (most recent and fastest)
      try {
        // Try direct query first
        final activeSnapshot = await _fs.activeSessionsRef()
            .where('phoneNumber', isEqualTo: cleanPhone)
            .limit(10)
            .get();

        if (activeSnapshot.docs.isNotEmpty) {
          for (var doc in activeSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            foundSessions.add(data);
          }
          // If found in active sessions, return immediately (most recent)
          if (foundSessions.isNotEmpty) {
            return foundSessions.first;
          }
        }
      } catch (e) {
        // If query fails (no index), try getting all active sessions and filter manually
        try {
          final allActive = await _fs.activeSessionsRef().limit(50).get();
          for (var doc in allActive.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final sessionPhone = data['phoneNumber'] as String?;
            if (sessionPhone != null) {
              final cleanSessionPhone = sessionPhone.replaceAll(RegExp(r'[^\d]'), '');
              if (cleanSessionPhone == cleanPhone) {
                foundSessions.add(data);
                // Return first match from active sessions immediately
                return data;
              }
            }
          }
        } catch (e2) {
          print('Error searching active sessions: $e2');
        }
      }

      // Then search in history collections (days)
      // Search recent dates first (last 7 days) for speed, then expand if needed
      final now = DateTime.now();
      Map<String, dynamic>? mostRecentSession;
      Timestamp? mostRecentTime;
      
      // Search last 7 days first (most likely to find recent users)
      for (int i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dateId = DateFormat('yyyy-MM-dd').format(date);
        
        try {
          // Try simple query (no orderBy, no index needed)
          final snapshot = await _fs.historySessionsRef(dateId)
              .where('phoneNumber', isEqualTo: cleanPhone)
              .limit(10)
              .get();

          if (snapshot.docs.isNotEmpty) {
            // Find the most recent session from this date
            for (var doc in snapshot.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final endTime = data['endTime'] as Timestamp?;
              final startTime = data['startTime'] as Timestamp?;
              
              // Compare with current most recent
              if (endTime != null) {
                if (mostRecentTime == null || endTime.compareTo(mostRecentTime) > 0) {
                  mostRecentTime = endTime;
                  mostRecentSession = data;
                }
              } else if (startTime != null) {
                if (mostRecentTime == null || startTime.compareTo(mostRecentTime) > 0) {
                  mostRecentTime = startTime;
                  mostRecentSession = data;
                }
              } else if (mostRecentSession == null) {
                // If no time available, use this as fallback
                mostRecentSession = data;
              }
            }
          }
        } catch (e) {
          // Skip this date if query fails
          continue;
        }
      }

      // If found in recent 7 days, return immediately
      if (mostRecentSession != null) {
        return mostRecentSession;
      }

      // If not found in recent 7 days, search next 23 days (total 30 days)
      for (int i = 7; i < 30; i++) {
        final date = now.subtract(Duration(days: i));
        final dateId = DateFormat('yyyy-MM-dd').format(date);
        
        try {
          final snapshot = await _fs.historySessionsRef(dateId)
              .where('phoneNumber', isEqualTo: cleanPhone)
              .limit(10)
              .get();

          if (snapshot.docs.isNotEmpty) {
            for (var doc in snapshot.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final endTime = data['endTime'] as Timestamp?;
              final startTime = data['startTime'] as Timestamp?;
              
              if (endTime != null) {
                if (mostRecentTime == null || endTime.compareTo(mostRecentTime) > 0) {
                  mostRecentTime = endTime;
                  mostRecentSession = data;
                }
              } else if (startTime != null) {
                if (mostRecentTime == null || startTime.compareTo(mostRecentTime) > 0) {
                  mostRecentTime = startTime;
                  mostRecentSession = data;
                }
              } else if (mostRecentSession == null) {
                mostRecentSession = data;
              }
            }
          }
        } catch (e) {
          continue;
        }
      }

      return mostRecentSession;
    } catch (e) {
      // Log error for debugging
      print('Error in searchUserHistoryByPhone: $e');
      return null;
    }
  }

  Future<void> addService(
    String sessionId,
    Map<String, dynamic> service,
  ) async {
    final doc = await _fs.activeSessionsRef().doc(sessionId).get();

    if (!doc.exists) {
      throw Exception('Session does not exist');
    }

    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Session data is null');
    }

    final services = List<Map<String, dynamic>>.from(data['services'] ?? []);
    services.add(service);

    final currentTotal = (data['totalAmount'] ?? 0).toDouble();
    final newTotal = currentTotal + (service['price'] as num).toDouble();

    // Recalculate final amount if discount exists
    final discount = (data['discount'] ?? 0).toDouble();
    final finalAmount = (newTotal - discount).clamp(0.0, double.infinity);

    await _fs.activeSessionsRef().doc(sessionId).update({
      'services': services,
      'totalAmount': newTotal,
      if (discount > 0) 'finalAmount': finalAmount,
    });
  }

  Future<void> updateService(
    String sessionId,
    int serviceIndex,
    Map<String, dynamic> updatedService,
  ) async {
    final doc = await _fs.activeSessionsRef().doc(sessionId).get();
    final data = doc.data() as Map<String, dynamic>;
    final services = List<Map<String, dynamic>>.from(data['services'] ?? []);

    if (serviceIndex >= 0 && serviceIndex < services.length) {
      final oldPrice = (services[serviceIndex]['price'] as num).toDouble();
      final newPrice = (updatedService['price'] as num).toDouble();
      final priceDiff = newPrice - oldPrice;

      services[serviceIndex] = updatedService;

      final currentTotal = (data['totalAmount'] ?? 0).toDouble();
      final newTotal = currentTotal + priceDiff;
      
      // Recalculate final amount if discount exists
      final discount = (data['discount'] ?? 0).toDouble();
      final finalAmount = (newTotal - discount).clamp(0.0, double.infinity);

      await _fs.activeSessionsRef().doc(sessionId).update({
        'services': services,
        'totalAmount': newTotal,
        if (discount > 0) 'finalAmount': finalAmount,
      });
    }
  }

  Future<void> deleteService(String sessionId, int serviceIndex) async {
    final doc = await _fs.activeSessionsRef().doc(sessionId).get();
    final data = doc.data() as Map<String, dynamic>;
    final services = List<Map<String, dynamic>>.from(data['services'] ?? []);

    if (serviceIndex >= 0 && serviceIndex < services.length) {
      final removedPrice = (services[serviceIndex]['price'] as num).toDouble();
      services.removeAt(serviceIndex);

      final currentTotal = (data['totalAmount'] ?? 0).toDouble();
      final newTotal = (currentTotal - removedPrice).clamp(
        0.0,
        double.infinity,
      );
      
      // Recalculate final amount if discount exists
      final discount = (data['discount'] ?? 0).toDouble();
      final finalAmount = (newTotal - discount).clamp(0.0, double.infinity);

      await _fs.activeSessionsRef().doc(sessionId).update({
        'services': services,
        'totalAmount': newTotal,
        if (discount > 0) 'finalAmount': finalAmount,
      });
    }
  }

  Future<void> closeSession(String sessionId, double total) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final sessionDoc = await tx.get(_fs.activeSessionsRef().doc(sessionId));
      if (!sessionDoc.exists) return;

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final dateId = _fs.todayId();

      // Move session to history
      final historyData = {
        ...sessionData,
        'status': 'closed',
        'endTime': Timestamp.now(),
        'totalAmount': total,
        'sessionId': sessionId,
      };

      // Add to history collection
      tx.set(_fs.historySessionsRef(dateId).doc(sessionId), historyData);

      // Update day totals
      tx.set(_fs.dayRef(), {
        'totalAmount': FieldValue.increment(total),
        'totalUsers': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // Delete from active sessions
      tx.delete(_fs.activeSessionsRef().doc(sessionId));
    });
  }

  Future<void> updateHistorySession(
    String dateId,
    String sessionId,
    Map<String, dynamic> updates,
  ) async {
    await FirebaseFirestore.instance
        .collection('days')
        .doc(dateId)
        .collection('sessions')
        .doc(sessionId)
        .update(updates);
  }

  Future<void> applyDiscount(String sessionId, double discountAmount) async {
    final doc = await _fs.activeSessionsRef().doc(sessionId).get();
    if (!doc.exists) {
      throw Exception('Session does not exist');
    }

    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Session data is null');
    }

    final currentTotal = (data['totalAmount'] ?? 0).toDouble();
    final finalTotal = (currentTotal - discountAmount).clamp(0.0, double.infinity);

    await _fs.activeSessionsRef().doc(sessionId).update({
      'discount': discountAmount,
      'finalAmount': finalTotal,
    });
  }

  Future<void> removeDiscount(String sessionId) async {
    await _fs.activeSessionsRef().doc(sessionId).update({
      'discount': FieldValue.delete(),
      'finalAmount': FieldValue.delete(),
    });
  }

  Future<void> deleteActiveSession(String sessionId) async {
    await _fs.activeSessionsRef().doc(sessionId).delete();
  }

  Future<void> deleteHistorySession(
    String dateId,
    String sessionId,
    double amount,
  ) async {
    try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
        // STEP 1: DO ALL READS FIRST (Firestore requirement)
        final dayRef = FirebaseFirestore.instance.collection('days').doc(dateId);
        final financeRef = FirebaseFirestore.instance.collection('daily_finance').doc(dateId);
        
        final dayDoc = await tx.get(dayRef);
        final financeDoc = await tx.get(financeRef);

        // STEP 2: NOW DO ALL WRITES
      // Delete the session
        final sessionRef = FirebaseFirestore.instance
            .collection('days')
            .doc(dateId)
            .collection('sessions')
            .doc(sessionId);
        
        tx.delete(sessionRef);

        // Update day totals if day exists
      if (dayDoc.exists) {
        final dayData = dayDoc.data() as Map<String, dynamic>;
        final currentTotal = (dayData['totalAmount'] ?? 0).toDouble();
        final currentUsers = (dayData['totalUsers'] ?? 0);

        tx.update(dayRef, {
          'totalAmount': (currentTotal - amount).clamp(0.0, double.infinity),
          'totalUsers': (currentUsers - 1).clamp(0, double.infinity),
        });
      }

        // Update daily finance if it exists
        if (financeDoc.exists) {
          final financeData = financeDoc.data() as Map<String, dynamic>;
          final currentIncome = (financeData['income'] ?? 0).toDouble();
          final newIncome = (currentIncome - amount).clamp(0.0, double.infinity);

          tx.update(financeRef, {
            'income': newIncome,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      throw Exception('Failed to delete session: ${e.toString()}');
    }
  }

  CollectionReference sessionsRef() => _fs.activeSessionsRef();
}
