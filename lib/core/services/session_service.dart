import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  final FirebaseService _fs = FirebaseService();
  final _uuid = const Uuid();

  Future<String> createSession(String name) async {
    final id = _uuid.v4();
    await _fs.activeSessionsRef().doc(id).set({
      'sessionId': id,
      'customerName': name,
      'startTime': Timestamp.now(),
      'status': 'active',
      'services': [],
      'totalAmount': 0,
    });
    return id;
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
    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Delete the session
      tx.delete(
        FirebaseFirestore.instance
            .collection('days')
            .doc(dateId)
            .collection('sessions')
            .doc(sessionId),
      );

      // Update day totals
      final dayRef = FirebaseFirestore.instance.collection('days').doc(dateId);
      final dayDoc = await tx.get(dayRef);
      if (dayDoc.exists) {
        final dayData = dayDoc.data() as Map<String, dynamic>;
        final currentTotal = (dayData['totalAmount'] ?? 0).toDouble();
        final currentUsers = (dayData['totalUsers'] ?? 0);

        tx.update(dayRef, {
          'totalAmount': (currentTotal - amount).clamp(0.0, double.infinity),
          'totalUsers': (currentUsers - 1).clamp(0, double.infinity),
        });
      }
    });
  }

  CollectionReference sessionsRef() => _fs.activeSessionsRef();
}
