import 'package:flutter/material.dart';
import 'package:rowzow/core/services/session_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SessionProvider extends ChangeNotifier {
  final SessionService _service = SessionService();

  String? activeSessionId;
  double currentTotal = 0;
  List<Map<String, dynamic>> services = [];

  Future<void> createSession(String name) async {
    activeSessionId = await _service.createSession(name);
    currentTotal = 0;
    services = [];
    notifyListeners();
  }

  Future<void> loadSession(String sessionId) async {
    activeSessionId = sessionId;
    await refreshSession();
  }

  Future<void> refreshSession() async {
    if (activeSessionId == null) return;

    final doc = await _service.sessionsRef().doc(activeSessionId!).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      currentTotal = (data['totalAmount'] ?? 0).toDouble();
      services = List<Map<String, dynamic>>.from(data['services'] ?? []);
      notifyListeners();
    } else {
      // Session might have been closed
      activeSessionId = null;
      currentTotal = 0;
      services = [];
      notifyListeners();
    }
  }

  Future<void> addService(Map<String, dynamic> service) async {
    if (activeSessionId == null) {
      throw Exception('No active session. Please create a session first.');
    }
    try {
      await _service.addService(activeSessionId!, service);
      await refreshSession();
    } catch (e) {
      // Re-throw to let the caller handle it
      rethrow;
    }
  }

  Future<void> updateService(
    int index,
    Map<String, dynamic> updatedService,
  ) async {
    if (activeSessionId == null) return;
    await _service.updateService(activeSessionId!, index, updatedService);
    await refreshSession();
  }

  Future<void> deleteService(int index) async {
    if (activeSessionId == null) return;
    await _service.deleteService(activeSessionId!, index);
    await refreshSession();
  }

  Future<void> applyDiscount(double discountAmount) async {
    if (activeSessionId == null) return;
    await _service.applyDiscount(activeSessionId!, discountAmount);
    await refreshSession();
  }

  Future<void> removeDiscount() async {
    if (activeSessionId == null) return;
    await _service.removeDiscount(activeSessionId!);
    await refreshSession();
  }

  Future<void> closeSession() async {
    if (activeSessionId == null) return;
    
    // Get the final amount (with discount if applied)
    final doc = await _service.sessionsRef().doc(activeSessionId!).get();
    double finalTotal = currentTotal;
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      finalTotal = (data?['finalAmount'] ?? data?['totalAmount'] ?? currentTotal).toDouble();
    }
    
    await _service.closeSession(activeSessionId!, finalTotal);
    activeSessionId = null;
    currentTotal = 0;
    services = [];
    notifyListeners();
  }

  Future<void> deleteActiveSession(String sessionId) async {
    await _service.deleteActiveSession(sessionId);
    // If the deleted session was the active one, clear it
    if (activeSessionId == sessionId) {
      activeSessionId = null;
      currentTotal = 0;
      services = [];
      notifyListeners();
    }
  }

  CollectionReference sessionsRef() => _service.sessionsRef();
}
