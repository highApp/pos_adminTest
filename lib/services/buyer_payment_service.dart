import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/buyer_payment.dart';

class BuyerPaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'buyer_payments';

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
}
