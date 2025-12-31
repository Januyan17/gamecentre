import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';

class DailyResetService {
  final FirebaseService _fs = FirebaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// IMPORTANT: This service NEVER touches pricing settings.
  /// Pricing settings (PS4, PS5, Theatre, VR, etc.) are stored in 'settings/pricing'
  /// and can ONLY be changed by admin with correct password via PricingSettingsPage.
  /// Pricing settings are NEVER reset automatically.

  /// Check and perform daily reset if needed
  /// This should be called when the app starts
  ///
  /// IMPORTANT: This method ONLY moves active sessions to history.
  /// It does NOT touch pricing settings (PS4, PS5, Theatre, VR, etc.)
  /// Pricing settings are stored in 'settings/pricing' and are NEVER reset.
  /// Pricing can ONLY be changed by admin with password via PricingSettingsPage.
  Future<void> checkAndPerformDailyReset() async {
    try {
      final todayId = _fs.todayId();
      final yesterdayId = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now().subtract(const Duration(days: 1)));

      // Check if we've already reset for today
      final resetDoc =
          await _firestore.collection('daily_resets').doc(todayId).get();
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
          final finalAmount =
              ((sessionData['finalAmount'] ?? sessionData['totalAmount'] ?? 0)
                      as num)
                  .toDouble();

          // Move to history
          final historyData = <String, dynamic>{
            ...sessionData,
            'status': 'closed',
            'endTime': Timestamp.fromDate(
              DateTime.now()
                  .subtract(const Duration(days: 1))
                  .copyWith(hour: 23, minute: 59, second: 59),
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
          final existingTotal =
              ((yesterdayData?['totalAmount'] ?? 0) as num).toDouble();
          final existingUsers =
              ((yesterdayData?['totalUsers'] ?? 0) as num).toInt();

          batch.set(yesterdayDayRef, {
            'totalAmount': existingTotal + totalAmount,
            'totalUsers': existingUsers + totalUsers,
          }, SetOptions(merge: true));
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
        batch.set(_firestore.collection('daily_resets').doc(todayId), {
          'resetDate': todayId,
          'resetTimestamp': FieldValue.serverTimestamp(),
          'sessionsMoved': activeSessionsSnapshot.docs.length,
          'totalAmount': totalAmount,
          'totalUsers': totalUsers,
        });

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

      // IMPORTANT: Pricing settings (PS4, PS5, Theatre, VR, etc.) are NEVER reset.
      // Pricing is stored in 'settings/pricing' collection and can ONLY be changed
      // by admin with correct password via PricingSettingsPage.
      // Daily reset only moves sessions to history - it does NOT touch pricing settings.

      // Don't initialize today's day document - let admin manage amounts manually
      // The day document will be created when sessions are closed or manually by admin
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
