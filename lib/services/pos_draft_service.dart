import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pos_draft.dart';

class PosDraftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'pos_drafts';

  /// Save a new draft. Uses [draft.id] as document id.
  Future<void> saveDraft(PosDraft draft) async {
    await _firestore.collection(_collection).doc(draft.id).set(draft.toMap());
  }

  /// Stream of all drafts, newest first.
  Stream<List<PosDraft>> getDraftsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => PosDraft.fromMap(doc.data()))
          .toList();
    });
  }

  /// Get a single draft by id.
  Future<PosDraft?> getDraftById(String id) async {
    final doc = await _firestore.collection(_collection).doc(id).get();
    if (doc.exists && doc.data() != null) {
      return PosDraft.fromMap(doc.data()!);
    }
    return null;
  }

  /// Delete a draft by id.
  Future<void> deleteDraft(String id) async {
    await _firestore.collection(_collection).doc(id).delete();
  }
}
