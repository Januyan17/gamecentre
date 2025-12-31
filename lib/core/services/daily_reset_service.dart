import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';

class DailyResetService {
  final FirebaseService _fs = FirebaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check and perform daily reset if needed
  /// This should be called when the app starts
  Future<void> checkAndPerformDailyReset() async {
    try {
      final todayId = _fs.todayId();
      final yesterdayId = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(const Duration(days: 1)));

      // Check if we've already reset for today
      final resetDoc = await _firestore.collection('daily_resets').doc(todayId).get();
      if (resetDoc.exists) {
        // Already reset for today
        return;
      }

      // Get all active sessions
      final activeSessionsSnapshot = await _fs.activeSessionsRef().get();

      if (activeSessionsSnapshot.docs.isNotEmpty) {
        // Move all active sessions to yesterday's history
        final batch = _firestore.batch();
        double totalAmount = 0.0;
        int totalUsers = 0;

        for (var doc in activeSessionsSnapshot.docs) {
          final sessionData = doc.data() as Map<String, dynamic>?;
          if (sessionData == null) continue;
          
          final sessionId = doc.id;

          // Get final amount (with discount if exists)
          final finalAmount = ((sessionData['finalAmount'] ??
                  sessionData['totalAmount'] ??
                  0) as num)
              .toDouble();

          // Move to history
          final historyData = <String, dynamic>{
            ...sessionData,
            'status': 'closed',
            'endTime': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 1)).copyWith(
                    hour: 23,
                    minute: 59,
                    second: 59,
                  ),
            ),
            'totalAmount': finalAmount,
            'sessionId': sessionId,
            'autoClosed': true, // Mark as auto-closed
          };

          batch.set(
            _fs.historySessionsRef(yesterdayId).doc(sessionId),
            historyData,
          );

          // Update totals
          totalAmount += finalAmount;
          totalUsers += 1;
        }

        // Update yesterday's day totals
        final yesterdayDayRef = _firestore.collection('days').doc(yesterdayId);
        final yesterdayDayDoc = await yesterdayDayRef.get();
        if (yesterdayDayDoc.exists) {
          final yesterdayData = yesterdayDayDoc.data();
          final existingTotal = ((yesterdayData?['totalAmount'] ?? 0) as num).toDouble();
          final existingUsers = ((yesterdayData?['totalUsers'] ?? 0) as num).toInt();

          batch.set(
            yesterdayDayRef,
            {
              'totalAmount': existingTotal + totalAmount,
              'totalUsers': existingUsers + totalUsers,
            },
            SetOptions(merge: true),
          );
        } else {
          // Create new day document for yesterday
          batch.set(yesterdayDayRef, {
            'totalAmount': totalAmount,
            'totalUsers': totalUsers,
          });
        }

        // Delete all active sessions
        for (var doc in activeSessionsSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Mark reset as done for today
        batch.set(
          _firestore.collection('daily_resets').doc(todayId),
          {
            'resetDate': todayId,
            'resetTimestamp': FieldValue.serverTimestamp(),
            'sessionsMoved': activeSessionsSnapshot.docs.length,
            'totalAmount': totalAmount,
            'totalUsers': totalUsers,
          },
        );

        // Commit all changes
        await batch.commit();
      } else {
        // No active sessions, just mark reset as done
        await _firestore.collection('daily_resets').doc(todayId).set({
          'resetDate': todayId,
          'resetTimestamp': FieldValue.serverTimestamp(),
          'sessionsMoved': 0,
          'totalAmount': 0.0,
          'totalUsers': 0,
        });
      }

      // Initialize today's day document if it doesn't exist
      final todayDayRef = _firestore.collection('days').doc(todayId);
      final todayDayDoc = await todayDayRef.get();
      if (!todayDayDoc.exists) {
        await todayDayRef.set({
          'totalAmount': 0,
          'totalUsers': 0,
        });
      }
    } catch (e) {
      // Log error but don't crash the app
      print('Error in daily reset: $e');
    }
  }

  /// Manually trigger daily reset (for testing or manual use)
  Future<void> manualDailyReset() async {
    await checkAndPerformDailyReset();
  }
}

