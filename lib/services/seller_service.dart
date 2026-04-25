import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/seller.dart';
import '../models/due_payment.dart';
import '../models/sale.dart';
import '../models/expense.dart';
import '../models/credit_history.dart';
import 'expense_service.dart';

// Set to true only when debugging seller/borrow/profit logic (avoid log I/O in production)
bool get _sellerServiceDebug => kDebugMode && false;

/// Firestore may store dates as ISO [String] or [Timestamp].
DateTime? _parseFirestoreDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime _createdAtForSort(Map<String, dynamic> data) {
  return _parseFirestoreDate(data['createdAt']) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _saleCalendarDayFromHistoryData(Map<String, dynamic> data) {
  final d = _parseFirestoreDate(data['saleDate']);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

/// Dashboard borrow card: remaining `duePayment` on [seller_history] rows whose `saleDate`
/// (date-only) falls in the dashboard’s selected range (not all-time).
class UnpaidSalesDashboardTotals {
  const UnpaidSalesDashboardTotals({
    required this.periodOutstandingFromHistory,
    required this.allTimeOutstandingFromHistory,
  });

  /// Remaining due on bills dated inside the filter; updates when payments change `duePayment`.
  final double periodOutstandingFromHistory;

  /// Sum of every positive `duePayment` on [seller_history] (any `saleDate`); live from the same snapshot.
  final double allTimeOutstandingFromHistory;

  static const UnpaidSalesDashboardTotals empty = UnpaidSalesDashboardTotals(
    periodOutstandingFromHistory: 0,
    allTimeOutstandingFromHistory: 0,
  );
}

/// Per-seller remaining due on [seller_history] rows in a `saleDate` range (date-only, inclusive).
class TodaySellerDueSummary {
  const TodaySellerDueSummary({
    required this.sellerId,
    required this.sellerName,
    required this.remainingDue,
    required this.paidInPeriod,
  });

  final String sellerId;
  final String sellerName;
  final double remainingDue;
  final double paidInPeriod;
}

/// Borrow + real seller profit for the dashboard date filter, computed in one pass (one Firestore round-trip set).
class DashboardSellerProfitTotals {
  const DashboardSellerProfitTotals({
    required this.borrowProfit,
    required this.realProfit,
  });

  final double borrowProfit;
  final double realProfit;

  static const DashboardSellerProfitTotals zero = DashboardSellerProfitTotals(
    borrowProfit: 0,
    realProfit: 0,
  );
}

/// Merge two streams so that when either emits, the merged stream emits (used for listening to sales + seller_history).
Stream<Object?> _mergeStreams(Stream<QuerySnapshot> a, Stream<QuerySnapshot> b) {
  final controller = StreamController<Object?>.broadcast(sync: true);
  void onData(_) {
    if (!controller.isClosed) controller.add(null);
  }
  a.listen(onData);
  b.listen(onData);
  return controller.stream;
}

/// Combine latest values from two streams and emit only after both are available.
Stream<R> _combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A aValue, B bValue) combiner,
) {
  final controller = StreamController<R>.broadcast(sync: true);
  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;

  void emitIfReady() {
    if (!hasA || !hasB || controller.isClosed) return;
    controller.add(combiner(latestA as A, latestB as B));
  }

  late final StreamSubscription<A> subA;
  late final StreamSubscription<B> subB;

  subA = a.listen(
    (value) {
      latestA = value;
      hasA = true;
      emitIfReady();
    },
    onError: controller.addError,
  );
  subB = b.listen(
    (value) {
      latestB = value;
      hasB = true;
      emitIfReady();
    },
    onError: controller.addError,
  );

  controller.onCancel = () async {
    await subA.cancel();
    await subB.cancel();
  };
  return controller.stream;
}

/// Emit at most every [interval] so dashboard doesn't recompute on every Firestore change.
Stream<T> _throttleStream<T>(Stream<T> source, Duration interval) {
  DateTime? lastEmit;
  return source.map((T value) {
    final now = DateTime.now();
    if (lastEmit == null || now.difference(lastEmit!) >= interval) {
      lastEmit = now;
      return value;
    }
    return null;
  }).where((v) => v != null).cast<T>();
}

class SellerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'sellers';
  static const _dashboardThrottle = Duration(seconds: 25);

  /// Only [seller_history] rows with money still owed (small set vs full history).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchOpenDueHistoryDocs(
    String sellerId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .where('duePayment', isGreaterThan: 0)
          .orderBy('duePayment')
          .get();
      return snapshot.docs;
    } catch (e) {
      if (_sellerServiceDebug) {
        debugPrint('fetchOpenDueHistoryDocs index/fallback: $e');
      }
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      return snapshot.docs
          .where(
            (d) => (d.data()['duePayment'] ?? 0).toDouble() > 0,
          )
          .toList();
    }
  }
  /// Profit cards: cheaper reads than before, so allow slightly fresher updates.
  static const _dashboardProfitThrottle = Duration(seconds: 10);

  // Get all sellers stream
  Stream<List<Seller>> getSellersStream() {
    return _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Seller.fromMap(doc.data()))
          .where((seller) => seller.isActive)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  // Get total credit balance across all sellers (throttled for dashboard performance)
  Stream<double> getTotalCreditBalanceStream() {
    final source = _firestore
        .collection(_collection)
        .snapshots()
        .map((snapshot) {
      double totalCreditBalance = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final seller = Seller.fromMap(data);
        if (seller.isActive) {
          final creditBalance = (data['creditBalance'] ?? 0).toDouble();
          totalCreditBalance += creditBalance;
        }
      }
      return totalCreditBalance;
    });
    return _throttleStream(source, _dashboardThrottle);
  }

  // Add seller
  Future<void> addSeller(Seller seller) async {
    await _firestore.collection(_collection).doc(seller.id).set(seller.toMap());
  }

  // Update seller
  Future<void> updateSeller(Seller seller) async {
    await _firestore
        .collection(_collection)
        .doc(seller.id)
        .update(seller.toMap());
  }

  // Delete seller (soft delete)
  Future<void> deleteSeller(String sellerId) async {
    await _firestore
        .collection(_collection)
        .doc(sellerId)
        .update({'isActive': false});
  }

  // Get seller by ID
  Future<Seller?> getSellerById(String sellerId) async {
    final doc = await _firestore.collection(_collection).doc(sellerId).get();
    if (doc.exists) {
      return Seller.fromMap(doc.data()!);
    }
    return null;
  }

  // Check if seller name already exists (case-insensitive)
  Future<bool> sellerNameExists(String sellerName) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('name', isEqualTo: sellerName.trim())
          .get();
      
      // Also check case-insensitive by getting all sellers and comparing
      // This is more reliable than case-sensitive query
      if (snapshot.docs.isEmpty) {
        final allSellersSnapshot = await _firestore
            .collection(_collection)
            .get();
        
        for (var doc in allSellersSnapshot.docs) {
          final data = doc.data();
          final existingName = data['name'] as String?;
          if (existingName != null && 
              existingName.trim().toLowerCase() == sellerName.trim().toLowerCase()) {
            return true;
          }
        }
        return false;
      }
      
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error checking seller name existence: $e');
      return false;
    }
  }

  // Add seller history record
  Future<void> addSellerHistory({
    required String sellerId,
    required String saleId,
    required double saleAmount,
    required double amountPaid,
    required DateTime saleDate,
    /// POS "Description (Optional)" / notes — shown on seller history.
    String? description,
    String? referenceNumber,
    bool isManual = false,
  }) async {
    final duePayment = saleAmount > amountPaid ? saleAmount - amountPaid : 0.0;

    final data = <String, dynamic>{
      'sellerId': sellerId,
      'saleId': saleId,
      'saleAmount': saleAmount,
      'amountPaid': amountPaid,
      'duePayment': duePayment,
      'saleDate': saleDate.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    final note = description?.trim();
    if (note != null && note.isNotEmpty) {
      data['description'] = note;
    }
    final ref = referenceNumber?.trim();
    if (ref != null && ref.isNotEmpty) {
      data['referenceNumber'] = ref;
    }
    if (isManual) {
      data['isManual'] = true;
    }

    await _firestore.collection('seller_history').add(data);
  }

  /// Adds an opening-due record to seller_history (e.g. when importing sellers with existing due).
  Future<void> addOpeningDueToSellerHistory({
    required String sellerId,
    required double dueAmount,
    required DateTime date,
    String? referenceNumber,
  }) async {
    if (dueAmount <= 0) return;
    final data = <String, dynamic>{
      'sellerId': sellerId,
      'saleId': 'import_${const Uuid().v4()}',
      'saleAmount': dueAmount,
      'amountPaid': 0.0,
      'duePayment': dueAmount,
      'saleDate': date.toIso8601String(),
      'createdAt': date.toIso8601String(),
    };
    if (referenceNumber != null && referenceNumber.trim().isNotEmpty) {
      data['referenceNumber'] = referenceNumber.trim();
    }
    await _firestore.collection('seller_history').add(data);
  }

  /// Re-opens seller due when recovered cash is refunded back on item return.
  /// This prevents losing money in outstanding due after return/refund.
  Future<void> addRecoveryReversalDueEntry({
    required String sellerId,
    required String saleId,
    required double amount,
    DateTime? date,
  }) async {
    if (amount <= 0) return;
    final when = date ?? DateTime.now();
    final data = <String, dynamic>{
      'sellerId': sellerId,
      'saleId': '${saleId}_recovery_reversal_${const Uuid().v4()}',
      'saleAmount': amount,
      'amountPaid': 0.0,
      'duePayment': amount,
      'saleDate': when.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'recordType': 'recovery_reversal',
      'description': 'Recovery reversed due to returned items',
      'sourceSaleId': saleId,
    };
    await _firestore.collection('seller_history').add(data);
  }

  // Update seller history when items are returned
  // This reduces the due payment by the return amount
  Future<void> updateSellerHistoryForReturn(String saleId, double returnAmount) async {
    if (returnAmount <= 0) return; // No return, nothing to update
    
    try {
      if (_sellerServiceDebug) debugPrint('=== UPDATING SELLER HISTORY FOR RETURN ===');
      if (_sellerServiceDebug) debugPrint('Sale ID: $saleId');
      if (_sellerServiceDebug) debugPrint('Return Amount: $returnAmount');
      
      // Find the seller_history record for this sale
      final snapshot = await _firestore
          .collection('seller_history')
          .where('saleId', isEqualTo: saleId)
          .get();
      
      if (snapshot.docs.isEmpty) {
        if (_sellerServiceDebug) debugPrint('No seller_history record found for sale: $saleId');
        return; // No seller history, nothing to update
      }
      
      // Update each seller_history record (should be only one)
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final currentDue = (data['duePayment'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        
        if (_sellerServiceDebug) debugPrint('Current seller_history record:');
        if (_sellerServiceDebug) debugPrint('  - Sale Amount: $saleAmount');
        if (_sellerServiceDebug) debugPrint('  - Amount Paid: $amountPaid');
        if (_sellerServiceDebug) debugPrint('  - Current Due: $currentDue');
        
        // Reduce saleAmount by return amount (net sale amount after return)
        final newSaleAmount = saleAmount - returnAmount;
        
        // Recalculate due payment: newSaleAmount - amountPaid (but don't go below 0)
        // This ensures the due payment reflects the actual amount owed after return
        final newDue = (newSaleAmount - amountPaid).clamp(0.0, double.infinity);
        
        if (_sellerServiceDebug) debugPrint('After return:');
        if (_sellerServiceDebug) debugPrint('  - Return Amount: $returnAmount');
        if (_sellerServiceDebug) debugPrint('  - New Sale Amount: $newSaleAmount');
        if (_sellerServiceDebug) debugPrint('  - New Due: $newDue');
        
        // Update the seller_history record
        await _firestore.collection('seller_history').doc(doc.id).update({
          'saleAmount': newSaleAmount,
          'duePayment': newDue,
        });
        
        if (_sellerServiceDebug) debugPrint('✓ Seller history updated for return');
      }
      
      if (_sellerServiceDebug) debugPrint('=== END UPDATING SELLER HISTORY ===');
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error updating seller history for return: $e');
      // Don't throw - return processing should continue even if seller history update fails
    }
  }

  // Add due payment
  Future<void> addDuePayment(DuePayment duePayment) async {
    await _firestore.collection('due_payments').doc(duePayment.id).set(duePayment.toMap());
  }

  // Get due payments for a seller from seller_history table (unpaid only)
  Future<List<DuePayment>> getDuePaymentsForSeller(String sellerId) async {
    if (_sellerServiceDebug) debugPrint('=== FETCHING DUE PAYMENTS FOR SELLER ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    
    try {
      // Try to fetch with composite query (requires index)
      if (_sellerServiceDebug) debugPrint('Attempting composite query...');
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .where('duePayment', isGreaterThan: 0)
          .orderBy('createdAt', descending: true)
          .get();

      if (_sellerServiceDebug) debugPrint('Composite query successful. Found ${snapshot.docs.length} documents');
      
      // Convert seller_history records to DuePayment objects
      final payments = snapshot.docs.map((doc) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        if (_sellerServiceDebug) debugPrint('Document ${doc.id}: duePayment = $duePayment');
        return DuePayment(
          id: doc.id, // Use document ID from seller_history
          sellerId: data['sellerId'] ?? '',
          saleId: data['saleId'] ?? '',
          totalAmount: (data['saleAmount'] ?? 0).toDouble(),
          amountPaid: (data['amountPaid'] ?? 0).toDouble(),
          dueAmount: duePayment,
          createdAt: _parseFirestoreDate(data['createdAt']) ?? DateTime.now(),
          isPaid: false, // All fetched records have duePayment > 0, so they're unpaid
        );
      }).toList();
      
      if (_sellerServiceDebug) debugPrint('Converted ${payments.length} due payments');
      if (_sellerServiceDebug) debugPrint('Total due amount: ${payments.fold(0.0, (sum, p) => sum + p.dueAmount)}');
      if (_sellerServiceDebug) debugPrint('=== END FETCHING DUE PAYMENTS ===');
      
      return payments;
    } catch (e) {
      // Fallback: Fetch all seller_history records and filter in memory
      // This avoids needing a composite index
      if (_sellerServiceDebug) debugPrint('Composite index may be needed. Using fallback method: $e');
      if (_sellerServiceDebug) debugPrint('Fetching all seller_history records for seller...');
      
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      
      // Sort by createdAt descending manually
      final sortedDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aDate = _createdAtForSort(a.data());
          final bDate = _createdAtForSort(b.data());
          return bDate.compareTo(aDate);
        });

      if (_sellerServiceDebug) debugPrint('Found ${snapshot.docs.length} total seller_history records');

      // Filter and convert seller_history records to DuePayment objects
      final allPayments = <DuePayment>[];
      
      for (var doc in sortedDocs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        
        if (_sellerServiceDebug) debugPrint('Document ${doc.id}:');
        if (_sellerServiceDebug) debugPrint('  - saleAmount: $saleAmount');
        if (_sellerServiceDebug) debugPrint('  - amountPaid: $amountPaid');
        if (_sellerServiceDebug) debugPrint('  - duePayment: $duePayment');
        
        if (duePayment > 0) {
          allPayments.add(DuePayment(
            id: doc.id,
            sellerId: data['sellerId'] ?? '',
            saleId: data['saleId'] ?? '',
            totalAmount: saleAmount,
            amountPaid: amountPaid,
            dueAmount: duePayment,
            createdAt: _parseFirestoreDate(data['createdAt']) ?? DateTime.now(),
            isPaid: false,
          ));
        }
      }
      
      final payments = allPayments;

      if (_sellerServiceDebug) debugPrint('Filtered to ${payments.length} due payments');
      if (_sellerServiceDebug) debugPrint('Total due amount: ${payments.fold(0.0, (sum, p) => sum + p.dueAmount)}');
      if (_sellerServiceDebug) debugPrint('=== END FETCHING DUE PAYMENTS (FALLBACK) ===');
      
      return payments;
    }
  }

  /// Reduces [`duePayment`] on open [`seller_history`] rows for this seller.
  ///
  /// **Allocation:** rows whose bill [`saleDate`] is on the same calendar day as
  /// [prioritizeBillsWithSaleDateSameDayAs] are paid first (FIFO by `createdAt` within that group),
  /// then any other open rows by global FIFO. Pass the **payment / checkout** date so
  /// “Unpaid sales · Today” and the seller list match user expectations when paying same-day bills.
  /// Omit [prioritizeBillsWithSaleDateSameDayAs] for strict global FIFO (oldest `createdAt` first).
  ///
  /// **Both** of these flows call this before recording the payment on the sale / history:
  /// - POS checkout when cash is allocated to existing dues (`cashForExistingDues`).
  /// - Seller history → **Add manual due payment**.
  /// Offline POS replay ([`SellerPosCheckoutReplay`]) uses the same logic.
  ///
  /// Dashboard **Unpaid sales** / **Total borrow** read sums of `duePayment` from `seller_history`,
  /// so a successful call here is what makes those numbers go down.
  ///
  /// Same as [applyPaymentToDuePayments] but returns **total open due before** applying,
  /// computed from the same snapshot (avoids a second full [seller_history] read).
  ///
  /// Due rows are updated with [WriteBatch] (one round trip per batch, max 500 ops).
  Future<({double remainingPayment, double totalOpenDueBefore})>
      applyPaymentToDuePaymentsWithMetrics(
    String sellerId,
    double paymentAmount, {
    DateTime? prioritizeBillsWithSaleDateSameDayAs,
  }) async {
    if (_sellerServiceDebug) debugPrint('=== APPLYING PAYMENT TO DUE PAYMENTS ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    if (_sellerServiceDebug) debugPrint('Payment Amount: $paymentAmount');
    if (paymentAmount <= 0) {
      return (remainingPayment: paymentAmount, totalOpenDueBefore: 0.0);
    }

    final openDocs = await fetchOpenDueHistoryDocs(sellerId);

    double totalOpenDueBefore = 0.0;
    for (final doc in openDocs) {
      totalOpenDueBefore += (doc.data()['duePayment'] ?? 0).toDouble();
    }

    DateTime? priorityDay;
    final p = prioritizeBillsWithSaleDateSameDayAs;
    if (p != null) {
      priorityDay = DateTime(p.year, p.month, p.day);
    }

    final candidates = openDocs.toList();

    candidates.sort((a, b) {
      final da = a.data();
      final db = b.data();
      if (priorityDay != null) {
        final dayA = _saleCalendarDayFromHistoryData(da);
        final dayB = _saleCalendarDayFromHistoryData(db);
        final priA = dayA == priorityDay;
        final priB = dayB == priorityDay;
        if (priA != priB) {
          return priA ? -1 : 1;
        }
      }
      return _createdAtForSort(da).compareTo(_createdAtForSort(db));
    });

    if (_sellerServiceDebug) {
      debugPrint('Applying to ${candidates.length} open due rows (priority day: $priorityDay)');
    }

    double remainingPayment = paymentAmount;
    var batch = _firestore.batch();
    var opsInBatch = 0;

    Future<void> commitBatch() async {
      if (opsInBatch == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      opsInBatch = 0;
    }

    for (final doc in candidates) {
      if (remainingPayment <= 0) break;

      final data = doc.data();
      final currentDue = (data['duePayment'] ?? 0).toDouble();
      if (currentDue <= 0) continue;

      final paymentApplied =
          currentDue < remainingPayment ? currentDue : remainingPayment;
      final newDue = currentDue - paymentApplied;
      remainingPayment -= paymentApplied;

      if (_sellerServiceDebug) debugPrint('Record ${doc.id}:');
      if (_sellerServiceDebug) debugPrint('  - Current Due: $currentDue');
      if (_sellerServiceDebug) debugPrint('  - Payment Applied: $paymentApplied');
      if (_sellerServiceDebug) debugPrint('  - New Due: $newDue');

      batch.update(doc.reference, {
        'duePayment': newDue,
        'amountPaid': (data['amountPaid'] ?? 0).toDouble() + paymentApplied,
      });
      opsInBatch++;
      if (opsInBatch >= 500) {
        await commitBatch();
      }
    }
    await commitBatch();

    if (_sellerServiceDebug) {
      debugPrint('Remaining payment after applying to dues: $remainingPayment');
      debugPrint('=== END APPLYING PAYMENT ===');
    }

    return (
      remainingPayment: remainingPayment,
      totalOpenDueBefore: totalOpenDueBefore,
    );
  }

  /// Returns cash **not** applied to any bill (becomes seller credit or change upstream).
  Future<double> applyPaymentToDuePayments(
    String sellerId,
    double paymentAmount, {
    DateTime? prioritizeBillsWithSaleDateSameDayAs,
  }) async {
    final r = await applyPaymentToDuePaymentsWithMetrics(
      sellerId,
      paymentAmount,
      prioritizeBillsWithSaleDateSameDayAs: prioritizeBillsWithSaleDateSameDayAs,
    );
    return r.remainingPayment;
  }

  // Add credit balance to seller (stored in sellers collection)
  Future<void> addCreditBalance(String sellerId, double creditAmount, {String? description, String? referenceNumber}) async {
    if (creditAmount <= 0) return;
    
    if (_sellerServiceDebug) debugPrint('=== ADDING CREDIT BALANCE ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    if (_sellerServiceDebug) debugPrint('Credit Amount: $creditAmount');
    
    try {
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (sellerDoc.exists) {
        final currentCredit = (sellerDoc.data()?['creditBalance'] ?? 0).toDouble();
        final newCredit = currentCredit + creditAmount;
        
        await sellerRef.update({
          'creditBalance': newCredit,
        });
        
        // Add credit history
        await addCreditHistory(
          sellerId: sellerId,
          amount: creditAmount,
          balanceBefore: currentCredit,
          balanceAfter: newCredit,
          type: 'added',
          description: description,
          referenceNumber: referenceNumber,
        );
        
        if (_sellerServiceDebug) debugPrint('Credit balance updated: $currentCredit + $creditAmount = $newCredit');
      } else {
        if (_sellerServiceDebug) debugPrint('Seller not found: $sellerId');
      }
      
      if (_sellerServiceDebug) debugPrint('=== END ADDING CREDIT BALANCE ===');
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error adding credit balance: $e');
      rethrow;
    }
  }

  // Get credit balance for a seller
  Future<double> getCreditBalance(String sellerId) async {
    try {
      final sellerDoc = await _firestore.collection('sellers').doc(sellerId).get();
      if (sellerDoc.exists) {
        return (sellerDoc.data()?['creditBalance'] ?? 0).toDouble();
      }
      return 0.0;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getting credit balance: $e');
      return 0.0;
    }
  }

  // Use credit balance (subtract from seller's credit)
  // Returns the amount of credit actually used (may be less than requested if insufficient credit)
  Future<double> useCreditBalance(String sellerId, double amountToUse) async {
    if (amountToUse <= 0) return 0.0;
    
    if (_sellerServiceDebug) debugPrint('=== USING CREDIT BALANCE ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    if (_sellerServiceDebug) debugPrint('Amount to Use: $amountToUse');
    
    try {
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (sellerDoc.exists) {
        final currentCredit = (sellerDoc.data()?['creditBalance'] ?? 0).toDouble();
        final creditUsed = currentCredit < amountToUse ? currentCredit : amountToUse;
        final newCredit = currentCredit - creditUsed;
        
        await sellerRef.update({
          'creditBalance': newCredit.clamp(0.0, double.infinity),
        });
        
        // Add credit history
        if (creditUsed > 0) {
          await addCreditHistory(
            sellerId: sellerId,
            amount: -creditUsed,
            balanceBefore: currentCredit,
            balanceAfter: newCredit,
            type: 'used',
            description: 'Credit used for sale',
          );
        }
        
        if (_sellerServiceDebug) debugPrint('Credit balance used: $currentCredit - $creditUsed = $newCredit');
        if (_sellerServiceDebug) debugPrint('=== END USING CREDIT BALANCE ===');
        
        return creditUsed;
      } else {
        if (_sellerServiceDebug) debugPrint('Seller not found: $sellerId');
        return 0.0;
      }
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error using credit balance: $e');
      return 0.0;
    }
  }

  // Reduce credit balance (for manual payments - does NOT create expenses)
  // This is used when seller pays manually to reduce their credit balance
  Future<void> reduceCreditBalance(
    String sellerId,
    double amountToReduce, {
    String? description,
    String? referenceNumber,
  }) async {
    if (amountToReduce <= 0) return;
    
    if (_sellerServiceDebug) debugPrint('=== REDUCING CREDIT BALANCE ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    if (_sellerServiceDebug) debugPrint('Amount to Reduce: $amountToReduce');
    
    try {
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (!sellerDoc.exists) {
        if (_sellerServiceDebug) debugPrint('Seller not found: $sellerId');
        throw Exception('Seller not found');
      }
      
      final currentCredit = (sellerDoc.data()?['creditBalance'] ?? 0).toDouble();
      
      if (currentCredit <= 0) {
        if (_sellerServiceDebug) debugPrint('No credit balance to reduce');
        throw Exception('No credit balance available');
      }
      
      final amountReduced = currentCredit < amountToReduce ? currentCredit : amountToReduce;
      final newCredit = (currentCredit - amountReduced).clamp(0.0, double.infinity);
      
      await sellerRef.update({
        'creditBalance': newCredit,
      });
      
      if (_sellerServiceDebug) debugPrint('Credit balance reduced by: $amountReduced');
      if (_sellerServiceDebug) debugPrint('Credit balance: $currentCredit -> $newCredit');
      
      // Add credit history
      await addCreditHistory(
        sellerId: sellerId,
        amount: -amountReduced,
        balanceBefore: currentCredit,
        balanceAfter: newCredit,
        type: 'payment',
        description: description ?? 'Manual payment to reduce credit',
        referenceNumber: referenceNumber,
      );
      
      if (_sellerServiceDebug) debugPrint('Credit balance reduced: $currentCredit - $amountReduced = $newCredit');
      if (_sellerServiceDebug) debugPrint('=== END REDUCING CREDIT BALANCE ===');
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error reducing credit balance: $e');
      rethrow;
    }
  }

  // Add credit history record
  Future<void> addCreditHistory({
    required String sellerId,
    required double amount,
    required double balanceBefore,
    required double balanceAfter,
    required String type,
    String? description,
    String? referenceNumber,
  }) async {
    try {
      final creditHistory = CreditHistory(
        id: const Uuid().v4(),
        sellerId: sellerId,
        amount: amount,
        balanceBefore: balanceBefore,
        balanceAfter: balanceAfter,
        type: type,
        description: description,
        referenceNumber: referenceNumber,
        createdAt: DateTime.now(),
      );
      
      await _firestore
          .collection('credit_history')
          .doc(creditHistory.id)
          .set(creditHistory.toMap());
      
      if (_sellerServiceDebug) debugPrint('Credit history added: ${creditHistory.id}');
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error adding credit history: $e');
      // Don't throw - credit history is not critical for the main operation
    }
  }

  /// Fetch credit history for a seller with optional date range (for PDF export).
  Future<List<CreditHistory>> getCreditHistory(
    String sellerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final snapshot = await _firestore
        .collection('credit_history')
        .where('sellerId', isEqualTo: sellerId)
        .get();

    var list = snapshot.docs.map((doc) => CreditHistory.fromMap(doc.data())).toList();

    if (startDate != null || endDate != null) {
      list = list.where((record) {
        final d = record.createdAt;
        final recordDate = DateTime(d.year, d.month, d.day);
        if (startDate != null) {
          final start = DateTime(startDate.year, startDate.month, startDate.day);
          if (recordDate.isBefore(start)) return false;
        }
        if (endDate != null) {
          final end = DateTime(endDate.year, endDate.month, endDate.day);
          if (recordDate.isAfter(end)) return false;
        }
        return true;
      }).toList();
    }

    list.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // Oldest first for PDF
    return list;
  }

  // Get credit history stream for a seller
  // Uses in-memory sorting to avoid requiring a composite index
  Stream<List<CreditHistory>> getCreditHistoryStream(String sellerId) {
    return _firestore
        .collection('credit_history')
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) {
      final historyList = snapshot.docs.map((doc) {
        return CreditHistory.fromMap(doc.data());
      }).toList();
      
      // Sort by createdAt descending in memory (avoids needing composite index)
      historyList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return historyList;
    });
  }

  // Get total credit reductions (throttled for dashboard performance)
  Stream<double> getTotalCreditReductionsStream() {
    final source = _firestore
        .collection('credit_history')
        .snapshots()
        .map((snapshot) {
      double totalReductions = 0.0;
      if (_sellerServiceDebug) debugPrint('=== CALCULATING TOTAL CREDIT REDUCTIONS ===');
      if (_sellerServiceDebug) debugPrint('Total credit_history records: ${snapshot.docs.length}');
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final type = data['type'] ?? '';
        final sellerId = data['sellerId'] ?? '';
        if (amount < 0 && type == 'payment') {
          totalReductions += amount.abs();
          if (_sellerServiceDebug) debugPrint('Found credit reduction: ${doc.id}, amount: ${amount.abs()}, seller: $sellerId');
        }
      }
      if (_sellerServiceDebug) debugPrint('Total Credit Reductions: $totalReductions');
      if (_sellerServiceDebug) debugPrint('=== END CALCULATING CREDIT REDUCTIONS ===');
      return totalReductions;
    });
    return _throttleStream(source, _dashboardThrottle);
  }

  // Get total credit reductions by date range
  Future<double> getTotalCreditReductionsByDateRange(DateTime startDate, DateTime endDate) async {
    try {
      final snapshot = await _firestore
          .collection('credit_history')
          .get();
      
      double totalReductions = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final type = data['type'] ?? '';
        final createdAtStr = data['createdAt'];
        
        if (createdAtStr != null && amount < 0 && type == 'payment') {
          try {
            final createdAt = DateTime.parse(createdAtStr);
            // Check if within date range
            if (createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
                createdAt.isBefore(endDate.add(const Duration(seconds: 1)))) {
              totalReductions += amount.abs(); // Add absolute value
            }
          } catch (e) {
            if (_sellerServiceDebug) debugPrint('Error parsing createdAt in credit_history ${doc.id}: $e');
          }
        }
      }
      return totalReductions;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getting credit reductions by date range: $e');
      return 0.0;
    }
  }

  /// Stream of total credit reductions on or after [fromDate]. Use for revenue calculation when reset date is set.
  Stream<double> getTotalCreditReductionsFromDateStream(DateTime fromDate) {
    final start = fromDate.subtract(const Duration(seconds: 1));
    return _firestore.collection('credit_history').snapshots().map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final type = data['type'] ?? '';
        final createdAtStr = data['createdAt'];
        if (createdAtStr != null && amount < 0 && type == 'payment') {
          try {
            final createdAt = DateTime.parse(createdAtStr);
            if (!createdAt.isBefore(start)) total += amount.abs();
          } catch (_) {}
        }
      }
      return total;
    });
  }

  // Update credit balance to a new value
  // When credit balance is reduced, creates an expense entry to reduce Revenue and Total Revenue
  // This ensures that reducing credit balance properly reflects in the dashboard metrics
  Future<void> updateCreditBalance(String sellerId, double newCreditBalance) async {
    if (_sellerServiceDebug) debugPrint('=== UPDATING CREDIT BALANCE ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    if (_sellerServiceDebug) debugPrint('New Credit Balance: $newCreditBalance');
    
    try {
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (!sellerDoc.exists) {
        if (_sellerServiceDebug) debugPrint('Seller not found: $sellerId');
        throw Exception('Seller not found');
      }
      
      final sellerData = sellerDoc.data()!;
      final seller = Seller.fromMap(sellerData);
      final oldCreditBalance = (sellerData['creditBalance'] ?? 0).toDouble();
      final creditDifference = oldCreditBalance - newCreditBalance;
      
      if (_sellerServiceDebug) debugPrint('Old Credit Balance: $oldCreditBalance');
      if (_sellerServiceDebug) debugPrint('New Credit Balance: $newCreditBalance');
      if (_sellerServiceDebug) debugPrint('Credit Difference: $creditDifference');
      
      // Update the credit balance
      await sellerRef.update({
        'creditBalance': newCreditBalance.clamp(0.0, double.infinity),
      });
      
      if (_sellerServiceDebug) debugPrint('Credit balance updated: $oldCreditBalance -> $newCreditBalance');
      if (creditDifference > 0) {
        if (_sellerServiceDebug) debugPrint('Credit balance reduced by: $creditDifference');
      } else if (creditDifference < 0) {
        if (_sellerServiceDebug) debugPrint('Credit balance increased by: ${creditDifference.abs()}');
      }
      
      if (_sellerServiceDebug) debugPrint('Credit balance updated to: $newCreditBalance');
      if (_sellerServiceDebug) debugPrint('=== END UPDATING CREDIT BALANCE ===');
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error updating credit balance: $e');
      rethrow;
    }
  }

  // Delete credit balance and all seller history records
  // This deletes all records related to the seller (seller_history entries)
  // Also creates an expense entry for the deleted credit balance amount to reduce revenue
  Future<void> deleteCreditBalanceWithHistory(String sellerId) async {
    if (_sellerServiceDebug) debugPrint('=== DELETING CREDIT BALANCE AND HISTORY ===');
    if (_sellerServiceDebug) debugPrint('Seller ID: $sellerId');
    
    try {
      // Get seller info and current credit balance before deleting
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (!sellerDoc.exists) {
        if (_sellerServiceDebug) debugPrint('Seller not found: $sellerId');
        throw Exception('Seller not found');
      }
      
      final sellerData = sellerDoc.data()!;
      final seller = Seller.fromMap(sellerData);
      final currentCreditBalance = (sellerData['creditBalance'] ?? 0).toDouble();
      
      if (_sellerServiceDebug) debugPrint('Current credit balance: $currentCreditBalance');
      if (_sellerServiceDebug) debugPrint('Seller name: ${seller.name}');
      
      // If credit balance > 0, create an expense entry to reduce revenue
      if (currentCreditBalance > 0) {
        final expenseService = ExpenseService();
        final expense = Expense(
          id: const Uuid().v4(),
          category: 'other',
          description: 'Credit balance deleted for seller: ${seller.name}',
          amount: currentCreditBalance,
          createdAt: DateTime.now(),
        );
        
        await expenseService.addExpense(expense);
        if (_sellerServiceDebug) debugPrint('Created expense entry: Rs. $currentCreditBalance to reduce revenue');
      }
      
      // Reset credit balance to 0
      await sellerRef.update({
        'creditBalance': 0.0,
      });
      
      // Delete all seller_history records for this seller
      final historySnapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      
      if (_sellerServiceDebug) debugPrint('Found ${historySnapshot.docs.length} seller_history records to delete');
      
      // Delete each history record
      for (var doc in historySnapshot.docs) {
        await doc.reference.delete();
        if (_sellerServiceDebug) debugPrint('Deleted seller_history record: ${doc.id}');
      }
      
      if (_sellerServiceDebug) debugPrint('Credit balance reset and ${historySnapshot.docs.length} history records deleted');
      if (currentCreditBalance > 0) {
        if (_sellerServiceDebug) debugPrint('Expense created to reduce revenue by: Rs. $currentCreditBalance');
      }
      if (_sellerServiceDebug) debugPrint('=== END DELETING CREDIT BALANCE AND HISTORY ===');
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error deleting credit balance and history: $e');
      rethrow;
    }
  }

  /// Migrate old manual due payment records: add recordType: 'payment' so they show simplified layout
  /// Returns number of records updated
  Future<int> migrateOldSellerPaymentRecords() async {
    try {
      final snapshot = await _firestore
          .collection('seller_history')
          .where('isManual', isEqualTo: true)
          .get();

      int updated = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['recordType'] != null) continue; // Already has recordType

        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final saleId = data['saleId'] as String?;

        // Must look like a payment: duePayment=0, amountPaid==saleAmount, saleAmount>0
        if (duePayment != 0 || amountPaid != saleAmount || saleAmount <= 0) continue;
        if (saleId == null || saleId.isEmpty) continue;

        try {
          final saleDoc = await _firestore.collection('sales').doc(saleId).get();
          if (!saleDoc.exists) continue;

          final saleData = saleDoc.data();
          final total = (saleData?['total'] ?? 0).toDouble();
          final items = saleData?['items'] as List<dynamic>?;

          // Manual due payment: sale has total=0, no items
          if (total == 0 && (items == null || items.isEmpty)) {
            await doc.reference.update({'recordType': 'payment'});
            updated++;
          }
        } catch (_) {
          // Skip on error
        }
      }
      return updated;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error migrating seller payment records: $e');
      rethrow;
    }
  }

  /// Repairs clear recovery mismatches for manual payment sales.
  ///
  /// Safe scope only:
  /// - Uses `seller_history` rows identified as payment records.
  /// - Matches by `saleId` to `sales/{saleId}`.
  /// - Updates only when sale looks like a manual payment (`total == 0`, no items),
  ///   and `recoveryBalance` is lower than paid amount in history.
  ///
  /// Returns summary counters for admin UI.
  Future<Map<String, int>> repairManualPaymentRecoveryMismatches() async {
    int paymentRows = 0;
    int salesMatched = 0;
    int updated = 0;
    int skipped = 0;
    int missingSales = 0;

    final paymentBySaleId = <String, double>{};
    final history = await _firestore.collection('seller_history').get();
    for (final doc in history.docs) {
      final data = doc.data();
      final saleId = data['saleId'] as String?;
      if (saleId == null || saleId.isEmpty) continue;

      final recordType = data['recordType'] as String?;
      final isManual = data['isManual'] == true;
      final duePayment = (data['duePayment'] ?? 0).toDouble();
      final amountPaid = (data['amountPaid'] ?? 0).toDouble();
      final saleAmount = (data['saleAmount'] ?? 0).toDouble();
      final isPayment = recordType == 'payment' ||
          (isManual && duePayment == 0 && amountPaid == saleAmount && saleAmount > 0);
      if (!isPayment || amountPaid <= 0) continue;

      paymentRows++;
      paymentBySaleId[saleId] = (paymentBySaleId[saleId] ?? 0.0) + amountPaid;
    }

    final saleIds = paymentBySaleId.keys.toList();
    const chunkSize = 30;
    for (var i = 0; i < saleIds.length; i += chunkSize) {
      final chunk = saleIds.sublist(
        i,
        i + chunkSize > saleIds.length ? saleIds.length : i + chunkSize,
      );
      final salesSnap = await _firestore
          .collection('sales')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      final foundIds = <String>{};
      for (final saleDoc in salesSnap.docs) {
        foundIds.add(saleDoc.id);
        salesMatched++;
        final sale = saleDoc.data();
        final total = (sale['total'] ?? 0).toDouble();
        final items = sale['items'] as List<dynamic>?;
        final currentRecovery = (sale['recoveryBalance'] ?? 0).toDouble();
        final expectedRecovery = paymentBySaleId[saleDoc.id] ?? 0.0;

        final looksManualPaymentSale = total == 0 && (items == null || items.isEmpty);
        if (!looksManualPaymentSale) {
          skipped++;
          continue;
        }
        if (expectedRecovery <= currentRecovery) {
          skipped++;
          continue;
        }

        await saleDoc.reference.update({
          'recoveryBalance': expectedRecovery,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
        updated++;
      }
      missingSales += chunk.where((id) => !foundIds.contains(id)).length;
    }

    return {
      'paymentRows': paymentRows,
      'salesMatched': salesMatched,
      'updated': updated,
      'skipped': skipped,
      'missingSales': missingSales,
    };
  }

  // Get total due amount for a seller from seller_history table
  Future<double> getTotalDueAmountForSeller(String sellerId) async {
    final result = await getTotalDueAndReferenceForSeller(sellerId);
    return result.$1;
  }

  /// Returns (totalDue, referenceNumber from seller_history).
  /// Total due uses **open-due rows only** (same as UI outstanding). Reference prefers recent docs (capped reads).
  Future<(double, String?)> getTotalDueAndReferenceForSeller(String sellerId) async {
    try {
      final openDocs = await fetchOpenDueHistoryDocs(sellerId);
      double totalDue = 0.0;
      for (final doc in openDocs) {
        totalDue += (doc.data()['duePayment'] ?? 0).toDouble();
      }

      String? referenceNumber;
      DateTime? latestWithRef;

      try {
        final recent = await _firestore
            .collection('seller_history')
            .where('sellerId', isEqualTo: sellerId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get();
        for (final doc in recent.docs) {
          final data = doc.data();
          final ref = data['referenceNumber'] as String?;
          final createdAt = _parseFirestoreDate(data['createdAt']);
          if (ref != null && ref.trim().isNotEmpty && createdAt != null) {
            if (latestWithRef == null || createdAt.isAfter(latestWithRef)) {
              latestWithRef = createdAt;
              referenceNumber = ref.trim();
            }
          }
        }
      } catch (_) {
        for (final doc in openDocs) {
          final data = doc.data();
          final ref = data['referenceNumber'] as String?;
          final createdAt = _parseFirestoreDate(data['createdAt']);
          if (ref != null && ref.trim().isNotEmpty && createdAt != null) {
            if (latestWithRef == null || createdAt.isAfter(latestWithRef)) {
              latestWithRef = createdAt;
              referenceNumber = ref.trim();
            }
          }
        }
      }

      return (totalDue, referenceNumber);
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getTotalDueAndReferenceForSeller: $e');
      return (0.0, null);
    }
  }

  /// Total payments received from this seller (all time): manual due payments only.
  Future<double> getTotalPaymentsReceivedForSeller(String sellerId) async {
    try {
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();

      double total = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final recordType = data['recordType'] as String?;
        final isManual = data['isManual'] == true;
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();

        final isPayment = recordType == 'payment' ||
            (isManual && duePayment == 0 && amountPaid == saleAmount && saleAmount > 0);
        if (isPayment) total += saleAmount;
      }
      return total;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getTotalPaymentsReceivedForSeller: $e');
      return 0.0;
    }
  }

  /// Returns seller IDs that had due payment (money received) or credit (add/reduce) activity
  /// during [startDate]–[endDate]. Used to filter the Sellers list by “activity in period”.
  Future<Set<String>> getSellerIdsWithDueOrCreditActivityInDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    final sellerIds = <String>{};

    try {
      // Due payments: seller_history records that are "payment" type with saleDate in range
      final historySnapshot = await _firestore.collection('seller_history').get();
      for (var doc in historySnapshot.docs) {
        final data = doc.data();
        final saleDate = _parseFirestoreDate(data['saleDate']);
        if (saleDate == null) continue;
        if (saleDate.isBefore(start) || saleDate.isAfter(end)) continue;

        final recordType = data['recordType'] as String?;
        final isManual = data['isManual'] == true;
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final isPayment = recordType == 'payment' ||
            (isManual && duePayment == 0 && amountPaid == saleAmount && saleAmount > 0);
        if (isPayment) {
          final sid = data['sellerId'] as String?;
          if (sid != null && sid.isNotEmpty) sellerIds.add(sid);
        }
      }

      // Credit activity: credit_history with createdAt in range
      final creditSnapshot = await _firestore.collection('credit_history').get();
      for (var doc in creditSnapshot.docs) {
        final data = doc.data();
        final createdAtStr = data['createdAt'];
        if (createdAtStr == null) continue;
        DateTime? createdAt;
        try {
          createdAt = DateTime.parse(createdAtStr);
        } catch (_) {
          continue;
        }
        if (createdAt.isBefore(start) || createdAt.isAfter(end)) continue;
        final sid = data['sellerId'] as String?;
        if (sid != null && sid.isNotEmpty) sellerIds.add(sid);
      }

      return sellerIds;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getSellerIdsWithDueOrCreditActivityInDateRange: $e');
      return {};
    }
  }

  /// Net sales total from [sales] (not full [seller_history] scan). Excludes payment-stub docs (net 0).
  Future<double> getNetSalesTotalForSeller(String sellerId) async {
    try {
      final snapshot = await _firestore
          .collection('sales')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      var total = 0.0;
      for (final doc in snapshot.docs) {
        try {
          total += Sale.fromMap(doc.data()).netTotal;
        } catch (_) {
          final data = doc.data();
          final t = (data['total'] ?? 0).toDouble();
          final r = (data['returnedAmount'] ?? 0).toDouble();
          total += t - r;
        }
      }
      return total;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getNetSalesTotalForSeller: $e');
      return 0.0;
    }
  }

  /// Total sales for this seller (all time), from [sales] documents.
  Future<double> getTotalSalesForSeller(String sellerId) async {
    return getNetSalesTotalForSeller(sellerId);
  }

  // Get total unpaid sales amount by date range from seller_history collection
  // This calculates the actual current due amounts (which are updated when payments are made)
  Future<double> getTotalUnpaidSalesByDateRange(DateTime startDate, DateTime endDate) async {
    try {
      if (_sellerServiceDebug) debugPrint('=== CALCULATING TOTAL UNPAID SALES BY DATE RANGE ===');
      if (_sellerServiceDebug) debugPrint('Start Date: $startDate');
      if (_sellerServiceDebug) debugPrint('End Date: $endDate');
      
      // Only rows with open due (far fewer than full history)
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _firestore
            .collection('seller_history')
            .where('duePayment', isGreaterThan: 0)
            .orderBy('duePayment')
            .get();
      } catch (e) {
        if (_sellerServiceDebug) debugPrint('getTotalUnpaidSalesByDateRange fallback: $e');
        snapshot = await _firestore.collection('seller_history').get();
      }

      if (_sellerServiceDebug) debugPrint('Found ${snapshot.docs.length} seller_history records (open-due or all)');

      double totalUnpaid = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final saleDate = _parseFirestoreDate(data['saleDate']);
        if (saleDate == null) continue;
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        if (duePayment > 0 &&
            saleDate.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            saleDate.isBefore(endDate.add(const Duration(seconds: 1)))) {
          totalUnpaid += duePayment;
          if (_sellerServiceDebug) {
            debugPrint(
                'Record ${doc.id}: duePayment = $duePayment (Sale Date: $saleDate, Total so far: $totalUnpaid)');
          }
        }
      }

      if (_sellerServiceDebug) debugPrint('Total Unpaid Sales: $totalUnpaid');
      if (_sellerServiceDebug) debugPrint('=== END CALCULATION ===');
      return totalUnpaid;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getting unpaid sales: $e');
      return 0.0;
    }
  }

  // Get total unpaid sales amount (all unpaid sales regardless of date)
  // This is used for the borrow section to show current total owed
  Future<double> getTotalUnpaidSales() async {
    try {
      if (_sellerServiceDebug) debugPrint('=== CALCULATING TOTAL UNPAID SALES (ALL) ===');
      
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _firestore
            .collection('seller_history')
            .where('duePayment', isGreaterThan: 0)
            .orderBy('duePayment')
            .get();
      } catch (e) {
        if (_sellerServiceDebug) debugPrint('getTotalUnpaidSales fallback: $e');
        snapshot = await _firestore.collection('seller_history').get();
      }

      if (_sellerServiceDebug) debugPrint('Found ${snapshot.docs.length} seller_history records (open-due or all)');

      double totalUnpaid = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        if (duePayment > 0) {
          totalUnpaid += duePayment;
        }
      }

      if (_sellerServiceDebug) debugPrint('Total Unpaid Sales (All): $totalUnpaid');
      if (_sellerServiceDebug) debugPrint('=== END CALCULATION ===');
      return totalUnpaid;
    } catch (e) {
      if (_sellerServiceDebug) debugPrint('Error getting total unpaid sales: $e');
      return 0.0;
    }
  }

  /// [seller_history] listener: unpaid on bills whose `saleDate` (date-only) lies in the range.
  Stream<UnpaidSalesDashboardTotals> getUnpaidSalesDashboardTotalsStream(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final startDay =
        DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final endDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    final startIso = startDay.toIso8601String();
    final endIso = DateTime(
      endDay.year,
      endDay.month,
      endDay.day,
      23,
      59,
      59,
      999,
    ).toIso8601String();

    final periodSource = _firestore
        .collection('seller_history')
        .where('saleDate', isGreaterThanOrEqualTo: startIso)
        .where('saleDate', isLessThanOrEqualTo: endIso)
        .snapshots()
        .map((snapshot) {
      double periodOutstanding = 0.0;
      for (final doc in snapshot.docs) {
        final duePayment = (doc.data()['duePayment'] ?? 0).toDouble();
        if (duePayment > 0) periodOutstanding += duePayment;
      }
      return periodOutstanding;
    });

    final allTimeSource = _firestore
        .collection('seller_history')
        .where('duePayment', isGreaterThan: 0)
        .orderBy('duePayment')
        .snapshots()
        .map((snapshot) {
      double allTimeOutstanding = 0.0;
      for (final doc in snapshot.docs) {
        allTimeOutstanding += (doc.data()['duePayment'] ?? 0).toDouble();
      }
      return allTimeOutstanding;
    });

    final source = _combineLatest2<double, double, UnpaidSalesDashboardTotals>(
      periodSource,
      allTimeSource,
      (periodOutstanding, allTimeOutstanding) => UnpaidSalesDashboardTotals(
        periodOutstandingFromHistory: periodOutstanding,
        allTimeOutstandingFromHistory: allTimeOutstanding,
      ),
    );
    // Do not throttle: _throttleStream drops events within the window, so reduced `duePayment`
    // after a payment could be missed and "Total borrow" / unpaid would stay wrong until
    // another unrelated write (or a long wait). This map is cheap (one snapshot iteration).
    return source;
  }

  /// Sellers with positive `duePayment` on bills whose `saleDate` is in the range (inclusive, date-only).
  Future<List<TodaySellerDueSummary>> getOutstandingDueBySellerForDateRange(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    try {
      final snapshot = await _firestore.collection('seller_history').get();
      final startDay =
          DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
      final endDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
      final bySeller = <String, double>{};
      final paidInPeriodBySeller = <String, double>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final parsed = _parseFirestoreDate(data['saleDate']);
        if (parsed == null) continue;
        final saleDay = DateTime(parsed.year, parsed.month, parsed.day);
        if (saleDay.isBefore(startDay) || saleDay.isAfter(endDay)) {
          continue;
        }
        final sellerId = data['sellerId'] as String?;
        if (sellerId == null || sellerId.isEmpty) continue;

        final due = (data['duePayment'] ?? 0).toDouble();
        if (due > 0) {
          bySeller[sellerId] = (bySeller[sellerId] ?? 0) + due;
        }

        final recordType = data['recordType'] as String?;
        final isManual = data['isManual'] == true;
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final isPaymentRecord = recordType == 'payment' ||
            (isManual && due == 0 && amountPaid == saleAmount && saleAmount > 0);
        if (isPaymentRecord && amountPaid > 0) {
          paidInPeriodBySeller[sellerId] =
              (paidInPeriodBySeller[sellerId] ?? 0) + amountPaid;
        }
      }
      final sortedIds = bySeller.keys.toList()
        ..sort((a, b) => bySeller[b]!.compareTo(bySeller[a]!));
      final out = <TodaySellerDueSummary>[];
      for (final id in sortedIds) {
        final seller = await getSellerById(id);
        out.add(TodaySellerDueSummary(
          sellerId: id,
          sellerName: seller?.name ?? 'Unknown seller',
          remainingDue: bySeller[id]!,
          paidInPeriod: paidInPeriodBySeller[id] ?? 0.0,
        ));
      }
      return out;
    } catch (e) {
      if (_sellerServiceDebug) {
        debugPrint('getOutstandingDueBySellerForDateRange: $e');
      }
      return [];
    }
  }

  static const int _whereInChunkSize = 30;

  Future<void> _addSalesToMapByIds(
    Iterable<String> saleIds,
    Map<String, Sale> salesMap,
  ) async {
    final ids = saleIds.where((id) => id.isNotEmpty).toList();
    for (var i = 0; i < ids.length; i += _whereInChunkSize) {
      final chunk = ids.sublist(
        i,
        i + _whereInChunkSize > ids.length ? ids.length : i + _whereInChunkSize,
      );
      final snap = await _firestore
          .collection('sales')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        try {
          final sale = Sale.fromMap(doc.data());
          if (!sale.isBorrowPayment) {
            salesMap[sale.id] = sale;
          }
        } catch (e) {
          if (_sellerServiceDebug) {
            debugPrint('Error parsing sale ${doc.id}: $e');
          }
        }
      }
    }
  }

  /// Same date semantics as [getBorrowProfitStreamByDateRange] / [getRealProfitFromPaidStreamByDateRange]
  /// but loads only [seller_history] in range + referenced sales + [sales] in `createdAt` window for walk-ins.
  Future<DashboardSellerProfitTotals> _computeDashboardSellerProfitsForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final startPad = startDate.subtract(const Duration(seconds: 1));
    final endPad = endDate.add(const Duration(seconds: 1));
    final loIso = startPad.toIso8601String();
    final hiIso = endPad.toIso8601String();

    final historySnapshot = await _firestore
        .collection('seller_history')
        .where('saleDate', isGreaterThan: loIso)
        .where('saleDate', isLessThan: hiIso)
        .get();

    final saleIdsFromHistory = <String>{};
    for (final doc in historySnapshot.docs) {
      final data = doc.data();
      final saleId = data['saleId'];
      if (saleId is String && saleId.isNotEmpty) {
        saleIdsFromHistory.add(saleId);
      }
    }

    final salesMap = <String, Sale>{};
    await _addSalesToMapByIds(saleIdsFromHistory, salesMap);

    final rangeSalesSnap = await _firestore
        .collection('sales')
        .where('createdAt', isGreaterThan: loIso)
        .where('createdAt', isLessThan: hiIso)
        .get();

    for (final doc in rangeSalesSnap.docs) {
      try {
        final sale = Sale.fromMap(doc.data());
        if (!sale.isBorrowPayment) {
          salesMap[sale.id] = sale;
        }
      } catch (e) {
        if (_sellerServiceDebug) {
          debugPrint('Error parsing sale ${doc.id}: $e');
        }
      }
    }

    double totalBorrowProfit = 0.0;
    for (final doc in historySnapshot.docs) {
      final data = doc.data();
      final duePayment = (data['duePayment'] ?? 0).toDouble();
      final saleId = data['saleId'] ?? '';
      final saleAmount = (data['saleAmount'] ?? 0).toDouble();

      if (duePayment > 0 &&
          saleId.isNotEmpty &&
          salesMap.containsKey(saleId)) {
        final sale = salesMap[saleId]!;
        if (sale.profit > 0 && saleAmount > 0) {
          final unpaidRatio = duePayment / saleAmount;
          final netProfit = sale.netProfit;
          totalBorrowProfit += netProfit * unpaidRatio;
          if (_sellerServiceDebug) {
            debugPrint(
              'Borrow Profit (Filtered): Sale $saleId, Due: $duePayment, SaleAmount: $saleAmount, Ratio: $unpaidRatio',
            );
          }
        }
      }
    }

    double totalRealProfit = 0.0;
    final salePayments = <String, double>{};
    final saleAmounts = <String, double>{};
    final salesWithSellerHistory = <String>{};

    for (final doc in historySnapshot.docs) {
      final data = doc.data();
      final saleId = data['saleId'] ?? '';
      final amountPaid = (data['amountPaid'] ?? 0).toDouble();
      final saleAmount = (data['saleAmount'] ?? 0).toDouble();

      if (saleId.isNotEmpty && salesMap.containsKey(saleId)) {
        salePayments[saleId] = (salePayments[saleId] ?? 0.0) + amountPaid;
        saleAmounts[saleId] = saleAmount;
        salesWithSellerHistory.add(saleId);
      }
    }

    for (final entry in salePayments.entries) {
      final saleId = entry.key;
      final totalPaid = entry.value;
      final saleAmount = saleAmounts[saleId] ?? 0.0;

      if (totalPaid > 0 && saleAmount > 0 && salesMap.containsKey(saleId)) {
        final sale = salesMap[saleId]!;
        if (sale.profit > 0) {
          final paidRatio = (totalPaid / saleAmount).clamp(0.0, 1.0);
          final netProfit = sale.netProfit;
          totalRealProfit += netProfit * paidRatio;
          if (_sellerServiceDebug) {
            debugPrint(
              'Real Profit (Filtered): Sale $saleId, Total Paid: $totalPaid, SaleAmount: $saleAmount, Ratio: $paidRatio',
            );
          }
        }
      }
    }

    for (final sale in salesMap.values) {
      if (salesWithSellerHistory.contains(sale.id)) {
        continue;
      }
      if (!sale.createdAt.isAfter(startPad) ||
          !sale.createdAt.isBefore(endPad)) {
        continue;
      }
      if (sale.sellerId == null || sale.sellerId!.isEmpty) {
        final netTotal = sale.netTotal;
        final amountReceived = sale.amountPaid - sale.change;
        if (amountReceived >= netTotal && sale.profit > 0) {
          totalRealProfit += sale.netProfit;
          if (_sellerServiceDebug) {
            debugPrint(
              'Real Profit (No Seller, Filtered): Sale ${sale.id}, Profit: ${sale.netProfit}',
            );
          }
        }
      }
    }

    if (_sellerServiceDebug) {
      debugPrint(
        'DashboardSellerProfitTotals: borrow=$totalBorrowProfit real=$totalRealProfit',
      );
    }

    return DashboardSellerProfitTotals(
      borrowProfit: totalBorrowProfit,
      realProfit: totalRealProfit,
    );
  }

  /// Single throttled stream for both profit metrics (one shared recompute per tick).
  Stream<DashboardSellerProfitTotals> getDashboardSellerProfitTotalsStream(
    DateTime startDate,
    DateTime endDate,
  ) {
    final startPad = startDate.subtract(const Duration(seconds: 1));
    final endPad = endDate.add(const Duration(seconds: 1));
    final loIso = startPad.toIso8601String();
    final hiIso = endPad.toIso8601String();

    final source = _mergeStreams(
      _firestore
          .collection('sales')
          .where('createdAt', isGreaterThan: loIso)
          .where('createdAt', isLessThan: hiIso)
          .snapshots(),
      _firestore
          .collection('seller_history')
          .where('saleDate', isGreaterThan: loIso)
          .where('saleDate', isLessThan: hiIso)
          .snapshots(),
    ).asyncMap((_) => _computeDashboardSellerProfitsForRange(startDate, endDate));
    return _throttleStream(source, _dashboardProfitThrottle);
  }

  // Get total borrow profit stream (profit from unpaid portions of sales)
  // This calculates profit from unpaid sales that will be transferred to real profit when paid
  Stream<double> getBorrowProfitStream() {
    return _firestore
        .collection('seller_history')
        .snapshots()
        .asyncMap((snapshot) async {
      double totalBorrowProfit = 0.0;
      
      // Get all sales to calculate profit
      final salesSnapshot = await FirebaseFirestore.instance
          .collection('sales')
          .get();
      
      final salesMap = <String, Sale>{};
      for (var doc in salesSnapshot.docs) {
        try {
          final sale = Sale.fromMap(doc.data());
          // Only include actual sales, not borrow payments
          if (!sale.isBorrowPayment) {
            salesMap[sale.id] = sale;
          }
        } catch (e) {
          if (_sellerServiceDebug) debugPrint('Error parsing sale ${doc.id}: $e');
        }
      }
      
      // Calculate profit from unpaid portions
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final saleId = data['saleId'] ?? '';
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        
        if (duePayment > 0 && saleId.isNotEmpty && salesMap.containsKey(saleId)) {
          final sale = salesMap[saleId]!;
          if (sale.profit > 0 && saleAmount > 0) {
            // Calculate profit proportion for unpaid portion
            // Use current saleAmount (may have been reduced by returns)
            // Example: Sale 5000, Profit 1000, Due 2500 → Borrow Profit: 500 (2500/5000 * 1000)
            final unpaidRatio = duePayment / saleAmount;
            final netProfit = sale.netProfit; // Profit after returns
            final borrowProfit = netProfit * unpaidRatio;
            totalBorrowProfit += borrowProfit;
            if (_sellerServiceDebug) debugPrint('Borrow Profit: Sale $saleId, Due: $duePayment, SaleAmount: $saleAmount, Ratio: $unpaidRatio, Profit: $borrowProfit');
          }
        }
      }
      
      if (_sellerServiceDebug) debugPrint('Total Borrow Profit: $totalBorrowProfit');
      return totalBorrowProfit;
    });
  }

  // Get total real profit from paid portions stream
  // This calculates profit from all paid amounts including payments made to cover dues
  // When payments are made to cover dues, this profit increases (transfers from borrow profit)
  Stream<double> getRealProfitFromPaidStream() {
    return _firestore
        .collection('seller_history')
        .snapshots()
        .asyncMap((snapshot) async {
      double totalRealProfit = 0.0;
      
      // Get all sales to calculate profit
      final salesSnapshot = await FirebaseFirestore.instance
          .collection('sales')
          .get();
      
      final salesMap = <String, Sale>{};
      for (var doc in salesSnapshot.docs) {
        try {
          final sale = Sale.fromMap(doc.data());
          // Only include actual sales, not borrow payments
          if (!sale.isBorrowPayment) {
            salesMap[sale.id] = sale;
          }
        } catch (e) {
          if (_sellerServiceDebug) debugPrint('Error parsing sale ${doc.id}: $e');
        }
      }
      
      // Group by saleId to sum all payments for each sale
      final salePayments = <String, double>{};
      final saleAmounts = <String, double>{};
      final salesWithSellerHistory = <String>{};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final saleId = data['saleId'] ?? '';
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        
        if (saleId.isNotEmpty && salesMap.containsKey(saleId)) {
          // Sum all payments for this sale (including payments made to cover dues)
          salePayments[saleId] = (salePayments[saleId] ?? 0.0) + amountPaid;
          // Use the latest saleAmount (may have been reduced by returns)
          saleAmounts[saleId] = saleAmount;
          // Track which sales have seller history entries
          salesWithSellerHistory.add(saleId);
        }
      }
      
      // Calculate profit from total paid amounts (sales with sellers)
      for (var entry in salePayments.entries) {
        final saleId = entry.key;
        final totalPaid = entry.value;
        final saleAmount = saleAmounts[saleId] ?? 0.0;
        
        if (totalPaid > 0 && saleAmount > 0 && salesMap.containsKey(saleId)) {
          final sale = salesMap[saleId]!;
          if (sale.profit > 0) {
            // Calculate profit proportion for total paid amount. Cap ratio at 1.0: after a return,
            // seller_history.saleAmount is reduced but amountPaid can stay at original total, so
            // totalPaid/saleAmount can exceed 1 and would incorrectly inflate profit.
            final paidRatio = (totalPaid / saleAmount).clamp(0.0, 1.0);
            final netProfit = sale.netProfit; // Profit after returns
            final realProfit = netProfit * paidRatio;
            totalRealProfit += realProfit;
            if (_sellerServiceDebug) debugPrint('Real Profit: Sale $saleId, Total Paid: $totalPaid, SaleAmount: $saleAmount, Ratio: $paidRatio, Profit: $realProfit');
          }
        }
      }
      
      // Also calculate profit from sales without sellers that are fully paid
      // These sales don't have seller_history entries, so we need to add them separately
      for (var sale in salesMap.values) {
        // Skip if this sale already has seller history (already counted above)
        if (salesWithSellerHistory.contains(sale.id)) {
          continue;
        }
        
        // Only include sales without sellers that are fully paid
        // For sales without sellers, recoveryBalance should be 0
        // A sale is fully paid if (amountPaid - change) >= netTotal
        // This means the amount we actually received covers the net sale amount after returns
        if (sale.sellerId == null || sale.sellerId!.isEmpty) {
          final netTotal = sale.netTotal; // Total after returns
          final amountReceived = sale.amountPaid - sale.change; // Amount we actually received (excluding change returned)
          if (amountReceived >= netTotal && sale.profit > 0) {
            // Sale is fully paid, add full net profit
            final netProfit = sale.netProfit; // Profit after returns
            totalRealProfit += netProfit;
            if (_sellerServiceDebug) debugPrint('Real Profit (No Seller): Sale ${sale.id}, Amount Paid: ${sale.amountPaid}, Change: ${sale.change}, Amount Received: $amountReceived, Net Total: $netTotal, Profit: $netProfit');
          }
        }
      }
      
      if (_sellerServiceDebug) debugPrint('Total Real Profit from Paid: $totalRealProfit');
      return totalRealProfit;
    });
  }

  // Get real profit from paid portions by date range (throttled for dashboard performance)
  // Listens to BOTH sales and seller_history so that when a return is applied (sales doc updated),
  // profit recalculates and dashboard shows reduced profit (netProfit).
  /// Prefer [getDashboardSellerProfitTotalsStream] on the dashboard to avoid duplicate listeners.
  Stream<double> getRealProfitFromPaidStreamByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return getDashboardSellerProfitTotalsStream(startDate, endDate)
        .map((t) => t.realProfit);
  }

  // Get borrow profit by date range (throttled for dashboard performance)
  // Listens to BOTH sales and seller_history so returns reduce borrow profit (netProfit) and dashboard updates.
  /// Prefer [getDashboardSellerProfitTotalsStream] on the dashboard to avoid duplicate listeners.
  Stream<double> getBorrowProfitStreamByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return getDashboardSellerProfitTotalsStream(startDate, endDate)
        .map((t) => t.borrowProfit);
  }
}

