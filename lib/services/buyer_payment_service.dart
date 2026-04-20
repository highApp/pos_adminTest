import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_payment.dart';

class BuyerPaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'buyer_payments';
  static const String _counterDoc = 'counters/buyer_payment';

  /// Returns next 4-digit payment number (e.g. PAY-0001, PAY-0002)
  Future<String> getNextPaymentNumber() async {
    final list = await getNextPaymentNumbers(1);
    return list.first;
  }

  /// Allocates [count] sequential PAY numbers in **one** transaction (vs [count] transactions).
  Future<List<String>> getNextPaymentNumbers(int count) async {
    if (count <= 0) return [];
    return _firestore.runTransaction<List<String>>((tx) async {
      final ref = _firestore.doc(_counterDoc);
      final snapshot = await tx.get(ref);
      int last = 0;
      if (snapshot.exists && snapshot.data() != null) {
        last = (snapshot.data()!['lastNumber'] ?? 0) as int;
      }
      final numbers = <String>[];
      var current = last;
      for (var i = 0; i < count; i++) {
        current = current >= 9999 ? 1 : current + 1;
        numbers.add('PAY-${current.toString().padLeft(4, '0')}');
      }
      tx.set(ref, {'lastNumber': current});
      return numbers;
    });
  }

  // Add payment
  Future<void> addPayment(BuyerPayment payment) async {
    await _firestore.collection(_collection).doc(payment.id).set(payment.toMap());
  }

  /// Commits multiple payments in one or few round trips (Firestore batches, max 500 ops each).
  Future<void> addPaymentsBatch(List<BuyerPayment> payments) async {
    if (payments.isEmpty) return;
    var batch = _firestore.batch();
    var ops = 0;
    for (final payment in payments) {
      batch.set(
        _firestore.collection(_collection).doc(payment.id),
        payment.toMap(),
      );
      ops++;
      if (ops >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }
  }

  /// Total paid per bill, using chunked `whereIn` queries (few reads vs one per bill).
  Future<Map<String, double>> getTotalPaidByBillIds(List<String> billIds) async {
    final totals = <String, double>{};
    for (final id in billIds) {
      totals[id] = 0.0;
    }
    if (billIds.isEmpty) return totals;

    const maxIn = 30;
    for (var i = 0; i < billIds.length; i += maxIn) {
      final end = i + maxIn > billIds.length ? billIds.length : i + maxIn;
      final slice = billIds.sublist(i, end);
      final snapshot = await _firestore
          .collection(_collection)
          .where('billId', whereIn: slice)
          .get();
      for (final doc in snapshot.docs) {
        final payment = BuyerPayment.fromMap(doc.data());
        totals[payment.billId] =
            (totals[payment.billId] ?? 0.0) + payment.amount;
      }
    }
    return totals;
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

  /// Total buyer payments in date range (inclusive), for dashboard figures.
  Stream<double> getTotalPaidByDateRangeStream(
    DateTime startDate,
    DateTime endDate,
  ) {
    final start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    ).toIso8601String();
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    ).toIso8601String();

    return _firestore
        .collection(_collection)
        .where('paymentDate', isGreaterThanOrEqualTo: start)
        .where('paymentDate', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.fold<double>(0.0, (sum, doc) {
        final payment = BuyerPayment.fromMap(doc.data());
        return sum + payment.amount;
      });
    });
  }

  /// Buyer-wise paid summary in date range (inclusive), sorted by amount desc.
  Future<List<Map<String, dynamic>>> getBuyerPaidSummaryByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    ).toIso8601String();
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      23,
      59,
      59,
      999,
    ).toIso8601String();

    final paymentsSnap = await _firestore
        .collection(_collection)
        .where('paymentDate', isGreaterThanOrEqualTo: start)
        .where('paymentDate', isLessThanOrEqualTo: end)
        .get();

    if (paymentsSnap.docs.isEmpty) return [];

    final paidByBillId = <String, double>{};
    var totalPaymentsCount = 0;
    for (final doc in paymentsSnap.docs) {
      final payment = BuyerPayment.fromMap(doc.data());
      paidByBillId[payment.billId] = (paidByBillId[payment.billId] ?? 0.0) + payment.amount;
      totalPaymentsCount++;
    }

    final billIds = paidByBillId.keys.where((id) => id.isNotEmpty).toList();
    if (billIds.isEmpty) return [];

    final buyerNameByBillId = <String, String>{};
    final buyerIdByBillId = <String, String>{};
    const maxIn = 30;
    for (var i = 0; i < billIds.length; i += maxIn) {
      final endIdx = i + maxIn > billIds.length ? billIds.length : i + maxIn;
      final slice = billIds.sublist(i, endIdx);
      final billsSnap = await _firestore
          .collection('buyer_bills')
          .where(FieldPath.documentId, whereIn: slice)
          .get();
      for (final doc in billsSnap.docs) {
        final bill = BuyerBill.fromMap(doc.data());
        buyerNameByBillId[bill.id] = bill.buyerName;
        buyerIdByBillId[bill.id] = bill.buyerId;
      }
    }

    final byBuyer = <String, Map<String, dynamic>>{};
    for (final entry in paidByBillId.entries) {
      final billId = entry.key;
      final amount = entry.value;
      final buyerId = buyerIdByBillId[billId] ?? billId;
      final buyerName = buyerNameByBillId[billId] ?? 'Unknown buyer';

      final existing = byBuyer[buyerId];
      if (existing == null) {
        byBuyer[buyerId] = {
          'buyerId': buyerId,
          'buyerName': buyerName,
          'amount': amount,
        };
      } else {
        existing['amount'] = (existing['amount'] as double) + amount;
      }
    }

    final rows = byBuyer.values.toList()
      ..sort(
        (a, b) =>
            ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()),
      );

    for (final row in rows) {
      row['paymentsCount'] = totalPaymentsCount;
    }
    return rows;
  }

  // Get total paid amount for a bill
  Future<double> getTotalPaidForBill(String billId) async {
    final m = await getTotalPaidByBillIds([billId]);
    return m[billId] ?? 0.0;
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
