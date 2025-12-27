import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/borrow.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import 'sales_service.dart';

class BorrowService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'borrows';

  // Add new borrow
  Future<void> addBorrow(Borrow borrow) async {
    await _firestore.collection(_collection).doc(borrow.id).set(borrow.toMap());
  }

  // Get all borrows stream
  Stream<List<Borrow>> getBorrowsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Borrow.fromMap(doc.data());
      }).toList();
    });
  }

  // Get borrows by date range
  Stream<List<Borrow>> getBorrowsByDateRange(DateTime startDate, DateTime endDate) {
    return _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Borrow.fromMap(doc.data());
      }).toList();
    });
  }

  // Get total borrowed amount by date range (money borrowed from others)
  Future<double> getTotalBorrowedByDateRange(DateTime startDate, DateTime endDate) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('type', isEqualTo: 'borrowed')
          .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
          .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
          .get();

      double total = 0.0;
      for (var doc in snapshot.docs) {
        final borrow = Borrow.fromMap(doc.data());
        if (!borrow.isPaid) {
          total += borrow.amount;
        }
      }

      return total;
    } catch (e) {
      // If collection doesn't exist or query fails, return 0
      return 0.0;
    }
  }

  // Get total lent amount by date range (money lent to others)
  Future<double> getTotalLentByDateRange(DateTime startDate, DateTime endDate) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('type', isEqualTo: 'lent')
          .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
          .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
          .get();

      double total = 0.0;
      for (var doc in snapshot.docs) {
        final borrow = Borrow.fromMap(doc.data());
        if (!borrow.isPaid) {
          total += borrow.amount;
        }
      }

      return total;
    } catch (e) {
      // If collection doesn't exist or query fails, return 0
      return 0.0;
    }
  }

  // Get net borrow (borrowed - lent)
  Future<double> getNetBorrowByDateRange(DateTime startDate, DateTime endDate) async {
    final totalBorrowed = await getTotalBorrowedByDateRange(startDate, endDate);
    final totalLent = await getTotalLentByDateRange(startDate, endDate);
    return totalBorrowed - totalLent;
  }

  // Update borrow
  Future<void> updateBorrow(Borrow borrow) async {
    await _firestore.collection(_collection).doc(borrow.id).update(borrow.toMap());
  }

  // Delete borrow
  Future<void> deleteBorrow(String borrowId) async {
    await _firestore.collection(_collection).doc(borrowId).delete();
  }

  // Mark borrow as paid and create a sale record for revenue/recovery balance
  // This is for type='lent' - when someone pays back money they borrowed
  Future<void> markBorrowAsPaid(Borrow borrow, DateTime paymentDate) async {
    if (borrow.type == 'lent' && !borrow.isPaid) {
      // Create a sale record to increase revenue and recovery balance
      final salesService = SalesService();
      
      final borrowSale = Sale(
        id: const Uuid().v4(),
        items: [], // No items for borrow payment
        total: borrow.amount,
        profit: 0.0, // No profit on borrow payments
        amountPaid: borrow.amount,
        change: 0.0,
        createdAt: paymentDate,
        customerName: 'Borrow Payment - ${borrow.personName}',
        paymentMethod: 'cash',
        returnedAmount: 0.0,
        isPartialReturn: false,
        sellerId: null,
        recoveryBalance: borrow.amount, // Full amount is recovery balance (recovering lent money)
        isBorrowPayment: true, // Mark as borrow payment
      );
      
      // Save the sale to increase revenue and recovery balance
      await salesService.addSale(borrowSale);
      
      // Update borrow to mark as paid
      final updatedBorrow = Borrow(
        id: borrow.id,
        type: borrow.type,
        personName: borrow.personName,
        description: borrow.description,
        amount: borrow.amount,
        createdAt: borrow.createdAt,
        isPaid: true,
        paidAt: paymentDate,
      );
      
      await updateBorrow(updatedBorrow);
    }
  }
}

