import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/zakat_record.dart';

class ZakatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'zakat_records';
  static const String _settingsDoc = 'zakat';

  /// Save a Zakat record.
  Future<void> saveRecord(ZakatRecord record) async {
    await _firestore.collection(_collection).doc(record.id).set(record.toMap());
  }

  /// Stream of all Zakat records (newest first).
  Stream<List<ZakatRecord>> getRecordsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ZakatRecord.fromMap(doc.data()))
          .toList();
    });
  }

  /// Get nisab threshold (Rs.). Returns null if not set.
  Future<double?> getNisab() async {
    try {
      final doc = await _firestore.collection('app_settings').doc(_settingsDoc).get();
      if (!doc.exists) return null;
      final value = doc.data()?['nisab'];
      if (value == null) return null;
      return (value as num).toDouble();
    } catch (e) {
      debugPrint('Error getting nisab: $e');
      return null;
    }
  }

  /// Set nisab threshold (Rs.). Pass null to clear.
  Future<void> setNisab(double? value) async {
    await _firestore.collection('app_settings').doc(_settingsDoc).set({
      'nisab': value,
    }, SetOptions(merge: true));
  }

  /// Stream of nisab value for real-time updates.
  Stream<double?> getNisabStream() {
    return _firestore.collection('app_settings').doc(_settingsDoc).snapshots().map((doc) {
      if (!doc.exists) return null;
      final value = doc.data()?['nisab'];
      if (value == null) return null;
      return (value as num).toDouble();
    });
  }
}
