import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/balance_entry.dart';

class BalanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'balance_entries';

  // Add balance entry
  Future<void> addBalanceEntry(BalanceEntry entry) async {
    await _firestore.collection(_collection).doc(entry.id).set(entry.toMap());
  }

  // Get all balance entries stream
  Stream<List<BalanceEntry>> getBalanceEntriesStream() {
    return _firestore
        .collection(_collection)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return BalanceEntry.fromMap(doc.data());
      }).toList();
    });
  }

  // Get total balance stream (sum of all balance entries)
  Stream<double> getTotalBalanceStream() {
    return getBalanceEntriesStream().map((entries) {
      return entries.fold<double>(
        0.0,
        (sum, entry) => sum + entry.amount,
      );
    });
  }

  // Delete balance entry
  Future<void> deleteBalanceEntry(String entryId) async {
    await _firestore.collection(_collection).doc(entryId).delete();
  }

  // Update balance entry
  Future<void> updateBalanceEntry(BalanceEntry entry) async {
    await _firestore
        .collection(_collection)
        .doc(entry.id)
        .update(entry.toMap());
  }
}
