import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer_payment.dart';

class BuyerPaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'buyer_payments';
  static const String _counterDoc = 'counters/buyer_payment';

  /// Returns next 4-digit payment number (e.g. PAY-0001, PAY-0002)
  Future<String> getNextPaymentNumber() async {
    return _firestore.runTransaction<String>((tx) async {
      final ref = _firestore.doc(_counterDoc);
      final snapshot = await tx.get(ref);
      int last = 0;
      if (snapshot.exists && snapshot.data() != null) {
        last = (snapshot.data()!['lastNumber'] ?? 0) as int;
      }
      final next = last >= 9999 ? 1 : last + 1; // 1-9999
      tx.set(ref, {'lastNumber': next});
      return 'PAY-${next.toString().padLeft(4, '0')}';
    });
  }

  // Add payment
  Future<void> addPayment(BuyerPayment payment) async {
    await _firestore.collection(_collection).doc(payment.id).set(payment.toMap());
  }

  // Get all payments for a bill (sort in memory to avoid index requirement)
  Stream<List<BuyerPayment>> getPaymentsByBill(String billId) {
    return _firestore
        .collection(_collection)
        .where('billId', isEqualTo: billId)
        .snapshots()
        .map((snapshot) {
      final payments = snapshot.docs.map((doc) {
        return BuyerPayment.fromMap(doc.data());
      }).toList();
      
      // Sort by date descending in memory
      payments.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
      return payments;
    });
  }

  // Get total paid amount for a bill
  Future<double> getTotalPaidForBill(String billId) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('billId', isEqualTo: billId)
        .get();
    
    return snapshot.docs.fold<double>(
      0.0,
      (sum, doc) {
        final payment = BuyerPayment.fromMap(doc.data());
        return sum + payment.amount;
      },
    );
  }

  // Get total paid stream for a bill (real-time)
  Stream<double> getTotalPaidStreamForBill(String billId) {
    return _firestore
        .collection(_collection)
        .where('billId', isEqualTo: billId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.fold<double>(
        0.0,
        (sum, doc) {
          final payment = BuyerPayment.fromMap(doc.data());
          return sum + payment.amount;
        },
      );
    });
  }

  // Get all payments for a buyer (all bills)
  Stream<List<BuyerPayment>> getAllPaymentsForBuyer(List<String> billIds) {
    if (billIds.isEmpty) {
      return Stream.value([]);
    }
    
    // Get payments for all bills - we'll filter in memory
    return _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => BuyerPayment.fromMap(doc.data()))
          .where((payment) => billIds.contains(payment.billId))
          .toList()
        ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    });
  }

  // Delete payment
  Future<void> deletePayment(String paymentId) async {
    await _firestore.collection(_collection).doc(paymentId).delete();
  }

  // Update payment
  Future<void> updatePayment(BuyerPayment payment) async {
    await _firestore
        .collection(_collection)
        .doc(payment.id)
        .update(payment.toMap());
  }

  /// Get all payments (for migration)
  Future<List<BuyerPayment>> getAllPayments() async {
    final snapshot = await _firestore.collection(_collection).get();
    return snapshot.docs
        .map((doc) => BuyerPayment.fromMap(doc.data()))
        .toList();
  }

  /// Migrate old payments without batchId: group by same buyer + paymentDate + paymentType + createdAt within 5 seconds
  /// Returns number of payment groups updated
  Future<int> migrateOldPaymentsToAddBatchId({
    required Map<String, String> billIdToBuyerId,
  }) async {
    final allPayments = await getAllPayments();
    final paymentsWithoutBatchId = allPayments
        .where((p) => p.batchId == null || p.batchId!.isEmpty)
        .toList();

    if (paymentsWithoutBatchId.isEmpty) return 0;

    // Sort by createdAt
    paymentsWithoutBatchId.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    int groupsUpdated = 0;
    final processed = <String>{};

    for (var i = 0; i < paymentsWithoutBatchId.length; i++) {
      if (processed.contains(paymentsWithoutBatchId[i].id)) continue;

      final p = paymentsWithoutBatchId[i];
      final buyerId = billIdToBuyerId[p.billId] ?? '';
      final paymentDateKey = DateTime(p.paymentDate.year, p.paymentDate.month, p.paymentDate.day).toIso8601String();

      final group = <BuyerPayment>[p];
      processed.add(p.id);

      for (var j = i + 1; j < paymentsWithoutBatchId.length; j++) {
        if (processed.contains(paymentsWithoutBatchId[j].id)) continue;

        final q = paymentsWithoutBatchId[j];
        final qBuyerId = billIdToBuyerId[q.billId] ?? '';
        final qPaymentDateKey = DateTime(q.paymentDate.year, q.paymentDate.month, q.paymentDate.day).toIso8601String();

        final createdAtDiff = q.createdAt.difference(p.createdAt).inSeconds;
        if (buyerId == qBuyerId &&
            paymentDateKey == qPaymentDateKey &&
            p.paymentType == q.paymentType &&
            createdAtDiff >= 0 &&
            createdAtDiff <= 5) {
          group.add(q);
          processed.add(q.id);
        }
      }

      if (group.length >= 2) {
        final batchId = const Uuid().v4();
        for (var payment in group) {
          await _firestore.collection(_collection).doc(payment.id).update({'batchId': batchId});
        }
        groupsUpdated++;
      }
    }

    return groupsUpdated;
  }
}
