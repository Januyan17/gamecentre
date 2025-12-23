import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String todayId() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String dateId(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  DocumentReference dayRef() => _db.collection('days').doc(todayId());

  DocumentReference dayRefByDate(String dateId) =>
      _db.collection('days').doc(dateId);

  // Active sessions collection (separate from history)
  CollectionReference activeSessionsRef() => _db.collection('active_sessions');

  // History sessions for a specific date
  CollectionReference historySessionsRef(String dateId) =>
      _db.collection('days').doc(dateId).collection('sessions');

  // Legacy support - for backward compatibility
  CollectionReference sessionsRef() => activeSessionsRef();
}
