import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/buyer_bill.dart';

class BuyerBillService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'buyer_bills';

  // Add new bill
  Future<void> addBill(BuyerBill bill) async {
    await _firestore.collection(_collection).doc(bill.id).set(bill.toMap());
  }

  // Get all bills for a buyer (sort in memory to avoid index requirement)
  Stream<List<BuyerBill>> getBillsByBuyer(String buyerId) {
    return _firestore
        .collection(_collection)
        .where('buyerId', isEqualTo: buyerId)
        .snapshots()
        .map((snapshot) {
      final bills = snapshot.docs.map((doc) {
        return BuyerBill.fromMap(doc.data());
      }).toList();
      
      // Sort by date descending in memory
      bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bills;
    });
  }

  // Get all bills stream (sort in memory to avoid index requirement)
  Stream<List<BuyerBill>> getBillsStream() {
    return _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      final bills = snapshot.docs.map((doc) {
        return BuyerBill.fromMap(doc.data());
      }).toList();
      
      // Sort by date descending in memory
      bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bills;
    });
  }

  // Get bills by date range (filter and sort in memory to avoid composite index)
  Stream<List<BuyerBill>> getBillsByDateRange(DateTime startDate, DateTime endDate) {
    return _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      final bills = snapshot.docs.map((doc) {
        return BuyerBill.fromMap(doc.data());
      }).toList();
      
      // Filter by date range in memory
      final filteredBills = bills.where((bill) {
        final billDate = bill.createdAt;
        final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        
        return billDate.isAfter(startDateOnly.subtract(const Duration(days: 1))) &&
               billDate.isBefore(endDateOnly.add(const Duration(days: 1)));
      }).toList();
      
      // Sort by date descending in memory
      filteredBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filteredBills;
    });
  }

  // Get bills by buyer and date range (filter and sort in memory to avoid composite index)
  Stream<List<BuyerBill>> getBillsByBuyerAndDateRange(
    String buyerId,
    DateTime startDate,
    DateTime endDate,
  ) {
    return _firestore
        .collection(_collection)
        .where('buyerId', isEqualTo: buyerId)
        .snapshots()
        .map((snapshot) {
      final bills = snapshot.docs.map((doc) {
        return BuyerBill.fromMap(doc.data());
      }).toList();
      
      // Filter by date range in memory
      final filteredBills = bills.where((bill) {
        final billDate = bill.createdAt;
        final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
        final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        
        return billDate.isAfter(startDateOnly.subtract(const Duration(days: 1))) &&
               billDate.isBefore(endDateOnly.add(const Duration(days: 1)));
      }).toList();
      
      // Sort by date descending in memory
      filteredBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filteredBills;
    });
  }

  // Delete bill
  Future<void> deleteBill(String billId) async {
    await _firestore.collection(_collection).doc(billId).delete();
  }

  // Get bill by ID
  Future<BuyerBill?> getBillById(String billId) async {
    final doc = await _firestore.collection(_collection).doc(billId).get();
    if (doc.exists) {
      return BuyerBill.fromMap(doc.data()!);
    }
    return null;
  }
}
