import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/seller.dart';
import '../models/due_payment.dart';
import '../models/sale.dart';
import '../models/expense.dart';
import '../models/credit_history.dart';
import 'expense_service.dart';

class SellerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'sellers';

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

  // Get total credit balance across all sellers (real-time stream)
  // This automatically updates when credit balance changes (used in sales or edited)
  Stream<double> getTotalCreditBalanceStream() {
    return _firestore
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
      debugPrint('Error checking seller name existence: $e');
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
  }) async {
    final duePayment = saleAmount > amountPaid ? saleAmount - amountPaid : 0.0;
    
    await _firestore.collection('seller_history').add({
      'sellerId': sellerId,
      'saleId': saleId,
      'saleAmount': saleAmount,
      'amountPaid': amountPaid,
      'duePayment': duePayment,
      'saleDate': saleDate.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  // Update seller history when items are returned
  // This reduces the due payment by the return amount
  Future<void> updateSellerHistoryForReturn(String saleId, double returnAmount) async {
    if (returnAmount <= 0) return; // No return, nothing to update
    
    try {
      debugPrint('=== UPDATING SELLER HISTORY FOR RETURN ===');
      debugPrint('Sale ID: $saleId');
      debugPrint('Return Amount: $returnAmount');
      
      // Find the seller_history record for this sale
      final snapshot = await _firestore
          .collection('seller_history')
          .where('saleId', isEqualTo: saleId)
          .get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('No seller_history record found for sale: $saleId');
        return; // No seller history, nothing to update
      }
      
      // Update each seller_history record (should be only one)
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final currentDue = (data['duePayment'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        
        debugPrint('Current seller_history record:');
        debugPrint('  - Sale Amount: $saleAmount');
        debugPrint('  - Amount Paid: $amountPaid');
        debugPrint('  - Current Due: $currentDue');
        
        // Reduce saleAmount by return amount (net sale amount after return)
        final newSaleAmount = saleAmount - returnAmount;
        
        // Recalculate due payment: newSaleAmount - amountPaid (but don't go below 0)
        // This ensures the due payment reflects the actual amount owed after return
        final newDue = (newSaleAmount - amountPaid).clamp(0.0, double.infinity);
        
        debugPrint('After return:');
        debugPrint('  - Return Amount: $returnAmount');
        debugPrint('  - New Sale Amount: $newSaleAmount');
        debugPrint('  - New Due: $newDue');
        
        // Update the seller_history record
        await _firestore.collection('seller_history').doc(doc.id).update({
          'saleAmount': newSaleAmount,
          'duePayment': newDue,
        });
        
        debugPrint('✓ Seller history updated for return');
      }
      
      debugPrint('=== END UPDATING SELLER HISTORY ===');
    } catch (e) {
      debugPrint('Error updating seller history for return: $e');
      // Don't throw - return processing should continue even if seller history update fails
    }
  }

  // Add due payment
  Future<void> addDuePayment(DuePayment duePayment) async {
    await _firestore.collection('due_payments').doc(duePayment.id).set(duePayment.toMap());
  }

  // Get due payments for a seller from seller_history table (unpaid only)
  Future<List<DuePayment>> getDuePaymentsForSeller(String sellerId) async {
    debugPrint('=== FETCHING DUE PAYMENTS FOR SELLER ===');
    debugPrint('Seller ID: $sellerId');
    
    try {
      // Try to fetch with composite query (requires index)
      debugPrint('Attempting composite query...');
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .where('duePayment', isGreaterThan: 0)
          .orderBy('createdAt', descending: true)
          .get();

      debugPrint('Composite query successful. Found ${snapshot.docs.length} documents');
      
      // Convert seller_history records to DuePayment objects
      final payments = snapshot.docs.map((doc) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        debugPrint('Document ${doc.id}: duePayment = $duePayment');
        return DuePayment(
          id: doc.id, // Use document ID from seller_history
          sellerId: data['sellerId'] ?? '',
          saleId: data['saleId'] ?? '',
          totalAmount: (data['saleAmount'] ?? 0).toDouble(),
          amountPaid: (data['amountPaid'] ?? 0).toDouble(),
          dueAmount: duePayment,
          createdAt: data['createdAt'] != null
              ? DateTime.parse(data['createdAt'])
              : DateTime.now(),
          isPaid: false, // All fetched records have duePayment > 0, so they're unpaid
        );
      }).toList();
      
      debugPrint('Converted ${payments.length} due payments');
      debugPrint('Total due amount: ${payments.fold(0.0, (sum, p) => sum + p.dueAmount)}');
      debugPrint('=== END FETCHING DUE PAYMENTS ===');
      
      return payments;
    } catch (e) {
      // Fallback: Fetch all seller_history records and filter in memory
      // This avoids needing a composite index
      debugPrint('Composite index may be needed. Using fallback method: $e');
      debugPrint('Fetching all seller_history records for seller...');
      
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      
      // Sort by createdAt descending manually
      final sortedDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aDate = a.data()['createdAt'] != null
              ? DateTime.parse(a.data()['createdAt'])
              : DateTime(1970);
          final bDate = b.data()['createdAt'] != null
              ? DateTime.parse(b.data()['createdAt'])
              : DateTime(1970);
          return bDate.compareTo(aDate);
        });

      debugPrint('Found ${snapshot.docs.length} total seller_history records');

      // Filter and convert seller_history records to DuePayment objects
      final allPayments = <DuePayment>[];
      
      for (var doc in sortedDocs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        
        debugPrint('Document ${doc.id}:');
        debugPrint('  - saleAmount: $saleAmount');
        debugPrint('  - amountPaid: $amountPaid');
        debugPrint('  - duePayment: $duePayment');
        
        if (duePayment > 0) {
          allPayments.add(DuePayment(
            id: doc.id,
            sellerId: data['sellerId'] ?? '',
            saleId: data['saleId'] ?? '',
            totalAmount: saleAmount,
            amountPaid: amountPaid,
            dueAmount: duePayment,
            createdAt: data['createdAt'] != null
                ? DateTime.parse(data['createdAt'])
                : DateTime.now(),
            isPaid: false,
          ));
        }
      }
      
      final payments = allPayments;

      debugPrint('Filtered to ${payments.length} due payments');
      debugPrint('Total due amount: ${payments.fold(0.0, (sum, p) => sum + p.dueAmount)}');
      debugPrint('=== END FETCHING DUE PAYMENTS (FALLBACK) ===');
      
      return payments;
    }
  }

  // Update seller_history due payments when payment is applied
  // Returns remaining payment amount (which should be stored as credit if > 0)
  Future<double> applyPaymentToDuePayments(String sellerId, double paymentAmount) async {
    debugPrint('=== APPLYING PAYMENT TO DUE PAYMENTS ===');
    debugPrint('Seller ID: $sellerId');
    debugPrint('Payment Amount: $paymentAmount');
    
    try {
      // Try to fetch with composite query
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .where('duePayment', isGreaterThan: 0)
          .orderBy('createdAt') // Oldest first (ascending by default)
          .get();
      
      debugPrint('Found ${snapshot.docs.length} records with due payments');
      
      double remainingPayment = paymentAmount;
      
      // Apply payment to oldest due payments first
      for (var doc in snapshot.docs) {
        if (remainingPayment <= 0) break;
        
        final data = doc.data();
        final currentDue = (data['duePayment'] ?? 0).toDouble();
        
        if (currentDue > 0) {
          final paymentApplied = currentDue < remainingPayment ? currentDue : remainingPayment;
          final newDue = currentDue - paymentApplied;
          remainingPayment -= paymentApplied;
          
          debugPrint('Record ${doc.id}:');
          debugPrint('  - Current Due: $currentDue');
          debugPrint('  - Payment Applied: $paymentApplied');
          debugPrint('  - New Due: $newDue');
          
          // Update the seller_history record
          await _firestore.collection('seller_history').doc(doc.id).update({
            'duePayment': newDue,
            'amountPaid': (data['amountPaid'] ?? 0).toDouble() + paymentApplied,
          });
        }
      }
      
      debugPrint('Remaining payment after applying to dues: $remainingPayment');
      debugPrint('=== END APPLYING PAYMENT ===');
      
      return remainingPayment; // Return remaining payment amount (should be stored as credit if > 0)
    } catch (e) {
      // Fallback: Fetch all and sort manually
      debugPrint('Composite index may be needed. Using fallback: $e');
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      
      // Sort by createdAt ascending (oldest first)
      final sortedDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aDate = a.data()['createdAt'] != null
              ? DateTime.parse(a.data()['createdAt'])
              : DateTime(1970);
          final bDate = b.data()['createdAt'] != null
              ? DateTime.parse(b.data()['createdAt'])
              : DateTime(1970);
          return aDate.compareTo(bDate);
        });
      
      double remainingPayment = paymentAmount;
      
      // Apply payment to oldest due payments first
      for (var doc in sortedDocs) {
        if (remainingPayment <= 0) break;
        
        final data = doc.data();
        final currentDue = (data['duePayment'] ?? 0).toDouble();
        
        if (currentDue > 0) {
          final paymentApplied = currentDue < remainingPayment ? currentDue : remainingPayment;
          final newDue = currentDue - paymentApplied;
          remainingPayment -= paymentApplied;
          
          debugPrint('Record ${doc.id}:');
          debugPrint('  - Current Due: $currentDue');
          debugPrint('  - Payment Applied: $paymentApplied');
          debugPrint('  - New Due: $newDue');
          
          // Update the seller_history record
          await _firestore.collection('seller_history').doc(doc.id).update({
            'duePayment': newDue,
            'amountPaid': (data['amountPaid'] ?? 0).toDouble() + paymentApplied,
          });
        }
      }
      
      debugPrint('Remaining payment after applying to dues: $remainingPayment');
      debugPrint('=== END APPLYING PAYMENT (FALLBACK) ===');
      
      return remainingPayment;
    }
  }

  // Add credit balance to seller (stored in sellers collection)
  Future<void> addCreditBalance(String sellerId, double creditAmount, {String? description, String? referenceNumber}) async {
    if (creditAmount <= 0) return;
    
    debugPrint('=== ADDING CREDIT BALANCE ===');
    debugPrint('Seller ID: $sellerId');
    debugPrint('Credit Amount: $creditAmount');
    
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
        
        debugPrint('Credit balance updated: $currentCredit + $creditAmount = $newCredit');
      } else {
        debugPrint('Seller not found: $sellerId');
      }
      
      debugPrint('=== END ADDING CREDIT BALANCE ===');
    } catch (e) {
      debugPrint('Error adding credit balance: $e');
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
      debugPrint('Error getting credit balance: $e');
      return 0.0;
    }
  }

  // Use credit balance (subtract from seller's credit)
  // Returns the amount of credit actually used (may be less than requested if insufficient credit)
  Future<double> useCreditBalance(String sellerId, double amountToUse) async {
    if (amountToUse <= 0) return 0.0;
    
    debugPrint('=== USING CREDIT BALANCE ===');
    debugPrint('Seller ID: $sellerId');
    debugPrint('Amount to Use: $amountToUse');
    
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
        
        debugPrint('Credit balance used: $currentCredit - $creditUsed = $newCredit');
        debugPrint('=== END USING CREDIT BALANCE ===');
        
        return creditUsed;
      } else {
        debugPrint('Seller not found: $sellerId');
        return 0.0;
      }
    } catch (e) {
      debugPrint('Error using credit balance: $e');
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
    
    debugPrint('=== REDUCING CREDIT BALANCE ===');
    debugPrint('Seller ID: $sellerId');
    debugPrint('Amount to Reduce: $amountToReduce');
    
    try {
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (!sellerDoc.exists) {
        debugPrint('Seller not found: $sellerId');
        throw Exception('Seller not found');
      }
      
      final currentCredit = (sellerDoc.data()?['creditBalance'] ?? 0).toDouble();
      
      if (currentCredit <= 0) {
        debugPrint('No credit balance to reduce');
        throw Exception('No credit balance available');
      }
      
      final amountReduced = currentCredit < amountToReduce ? currentCredit : amountToReduce;
      final newCredit = (currentCredit - amountReduced).clamp(0.0, double.infinity);
      
      await sellerRef.update({
        'creditBalance': newCredit,
      });
      
      debugPrint('Credit balance reduced by: $amountReduced');
      debugPrint('Credit balance: $currentCredit -> $newCredit');
      
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
      
      debugPrint('Credit balance reduced: $currentCredit - $amountReduced = $newCredit');
      debugPrint('=== END REDUCING CREDIT BALANCE ===');
    } catch (e) {
      debugPrint('Error reducing credit balance: $e');
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
      
      debugPrint('Credit history added: ${creditHistory.id}');
    } catch (e) {
      debugPrint('Error adding credit history: $e');
      // Don't throw - credit history is not critical for the main operation
    }
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

  // Get total credit reductions (sum of all negative amounts from credit_history)
  // This represents money that was paid to reduce credit balance and should reduce revenue
  Stream<double> getTotalCreditReductionsStream() {
    return _firestore
        .collection('credit_history')
        .snapshots()
        .map((snapshot) {
      double totalReductions = 0.0;
      debugPrint('=== CALCULATING TOTAL CREDIT REDUCTIONS ===');
      debugPrint('Total credit_history records: ${snapshot.docs.length}');
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final type = data['type'] ?? '';
        final sellerId = data['sellerId'] ?? '';
        // Only count negative amounts (reductions) with type 'payment' (manual payments to reduce credit)
        if (amount < 0 && type == 'payment') {
          totalReductions += amount.abs(); // Add absolute value (since amount is negative)
          debugPrint('Found credit reduction: ${doc.id}, amount: ${amount.abs()}, seller: $sellerId');
        }
      }
      debugPrint('Total Credit Reductions: $totalReductions');
      debugPrint('=== END CALCULATING CREDIT REDUCTIONS ===');
      return totalReductions;
    });
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
            debugPrint('Error parsing createdAt in credit_history ${doc.id}: $e');
          }
        }
      }
      return totalReductions;
    } catch (e) {
      debugPrint('Error getting credit reductions by date range: $e');
      return 0.0;
    }
  }

  // Update credit balance to a new value
  // When credit balance is reduced, creates an expense entry to reduce Revenue and Total Revenue
  // This ensures that reducing credit balance properly reflects in the dashboard metrics
  Future<void> updateCreditBalance(String sellerId, double newCreditBalance) async {
    debugPrint('=== UPDATING CREDIT BALANCE ===');
    debugPrint('Seller ID: $sellerId');
    debugPrint('New Credit Balance: $newCreditBalance');
    
    try {
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (!sellerDoc.exists) {
        debugPrint('Seller not found: $sellerId');
        throw Exception('Seller not found');
      }
      
      final sellerData = sellerDoc.data()!;
      final seller = Seller.fromMap(sellerData);
      final oldCreditBalance = (sellerData['creditBalance'] ?? 0).toDouble();
      final creditDifference = oldCreditBalance - newCreditBalance;
      
      debugPrint('Old Credit Balance: $oldCreditBalance');
      debugPrint('New Credit Balance: $newCreditBalance');
      debugPrint('Credit Difference: $creditDifference');
      
      // Update the credit balance
      await sellerRef.update({
        'creditBalance': newCreditBalance.clamp(0.0, double.infinity),
      });
      
      debugPrint('Credit balance updated: $oldCreditBalance -> $newCreditBalance');
      if (creditDifference > 0) {
        debugPrint('Credit balance reduced by: $creditDifference');
      } else if (creditDifference < 0) {
        debugPrint('Credit balance increased by: ${creditDifference.abs()}');
      }
      
      debugPrint('Credit balance updated to: $newCreditBalance');
      debugPrint('=== END UPDATING CREDIT BALANCE ===');
    } catch (e) {
      debugPrint('Error updating credit balance: $e');
      rethrow;
    }
  }

  // Delete credit balance and all seller history records
  // This deletes all records related to the seller (seller_history entries)
  // Also creates an expense entry for the deleted credit balance amount to reduce revenue
  Future<void> deleteCreditBalanceWithHistory(String sellerId) async {
    debugPrint('=== DELETING CREDIT BALANCE AND HISTORY ===');
    debugPrint('Seller ID: $sellerId');
    
    try {
      // Get seller info and current credit balance before deleting
      final sellerRef = _firestore.collection('sellers').doc(sellerId);
      final sellerDoc = await sellerRef.get();
      
      if (!sellerDoc.exists) {
        debugPrint('Seller not found: $sellerId');
        throw Exception('Seller not found');
      }
      
      final sellerData = sellerDoc.data()!;
      final seller = Seller.fromMap(sellerData);
      final currentCreditBalance = (sellerData['creditBalance'] ?? 0).toDouble();
      
      debugPrint('Current credit balance: $currentCreditBalance');
      debugPrint('Seller name: ${seller.name}');
      
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
        debugPrint('Created expense entry: Rs. $currentCreditBalance to reduce revenue');
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
      
      debugPrint('Found ${historySnapshot.docs.length} seller_history records to delete');
      
      // Delete each history record
      for (var doc in historySnapshot.docs) {
        await doc.reference.delete();
        debugPrint('Deleted seller_history record: ${doc.id}');
      }
      
      debugPrint('Credit balance reset and ${historySnapshot.docs.length} history records deleted');
      if (currentCreditBalance > 0) {
        debugPrint('Expense created to reduce revenue by: Rs. $currentCreditBalance');
      }
      debugPrint('=== END DELETING CREDIT BALANCE AND HISTORY ===');
    } catch (e) {
      debugPrint('Error deleting credit balance and history: $e');
      rethrow;
    }
  }

  // Get total due amount for a seller from seller_history table
  Future<double> getTotalDueAmountForSeller(String sellerId) async {
    try {
      debugPrint('=== CALCULATING TOTAL DUE FOR SELLER: $sellerId ===');
      
      // Fetch all seller_history records for this seller
      final snapshot = await _firestore
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .get();

      debugPrint('Found ${snapshot.docs.length} seller_history records');

      // Check each record and sum duePayment amounts
      double totalDue = 0.0;
      int recordsWithDue = 0;
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final saleId = data['saleId'] ?? 'N/A';
        
        debugPrint('Record ${doc.id}:');
        debugPrint('  - Sale ID: $saleId');
        debugPrint('  - Sale Amount: $saleAmount');
        debugPrint('  - Amount Paid: $amountPaid');
        debugPrint('  - Due Payment: $duePayment');
        
        if (duePayment > 0) {
          recordsWithDue++;
          totalDue += duePayment;
          debugPrint('  - ✓ Added to total (Current total: $totalDue)');
        } else {
          debugPrint('  - ✗ No due payment (fully paid)');
        }
      }

      debugPrint('Total records with due payment: $recordsWithDue');
      debugPrint('Total Due Amount: $totalDue');
      debugPrint('=== END CALCULATION ===');

      return totalDue;
    } catch (e) {
      debugPrint('Error calculating total due amount: $e');
      return 0.0;
    }
  }

  // Get total unpaid sales amount by date range from seller_history collection
  // This calculates the actual current due amounts (which are updated when payments are made)
  Future<double> getTotalUnpaidSalesByDateRange(DateTime startDate, DateTime endDate) async {
    try {
      debugPrint('=== CALCULATING TOTAL UNPAID SALES BY DATE RANGE ===');
      debugPrint('Start Date: $startDate');
      debugPrint('End Date: $endDate');
      
      // Get all seller_history records and filter by date range in memory
      // This avoids needing a composite index and ensures we get accurate data
      final snapshot = await _firestore
          .collection('seller_history')
          .get();

      debugPrint('Found ${snapshot.docs.length} total seller_history records');

      double totalUnpaid = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        try {
          final saleDateStr = data['saleDate'];
          if (saleDateStr != null) {
            final saleDate = DateTime.parse(saleDateStr);
            final duePayment = (data['duePayment'] ?? 0).toDouble();
            
            // Check if sale date is within range and has unpaid amount
            if (duePayment > 0 && 
                saleDate.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
                saleDate.isBefore(endDate.add(const Duration(seconds: 1)))) {
              totalUnpaid += duePayment;
              debugPrint('Record ${doc.id}: duePayment = $duePayment (Sale Date: $saleDate, Total so far: $totalUnpaid)');
            }
          }
        } catch (parseError) {
          debugPrint('Error parsing seller_history record ${doc.id}: $parseError');
          continue;
        }
      }

      debugPrint('Total Unpaid Sales: $totalUnpaid');
      debugPrint('=== END CALCULATION ===');
      return totalUnpaid;
    } catch (e) {
      debugPrint('Error getting unpaid sales: $e');
      return 0.0;
    }
  }

  // Get total unpaid sales amount (all unpaid sales regardless of date)
  // This is used for the borrow section to show current total owed
  Future<double> getTotalUnpaidSales() async {
    try {
      debugPrint('=== CALCULATING TOTAL UNPAID SALES (ALL) ===');
      
      // Get all seller_history records
      final snapshot = await _firestore
          .collection('seller_history')
          .get();

      debugPrint('Found ${snapshot.docs.length} total seller_history records');

      double totalUnpaid = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        if (duePayment > 0) {
          totalUnpaid += duePayment;
        }
      }

      debugPrint('Total Unpaid Sales (All): $totalUnpaid');
      debugPrint('=== END CALCULATION ===');
      return totalUnpaid;
    } catch (e) {
      debugPrint('Error getting total unpaid sales: $e');
      return 0.0;
    }
  }

  // Get total unpaid sales stream (all unpaid sales regardless of date) - for real-time updates
  Stream<double> getTotalUnpaidSalesStream() {
    return _firestore
        .collection('seller_history')
        .snapshots()
        .map((snapshot) {
      double totalUnpaid = 0.0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        if (duePayment > 0) {
          totalUnpaid += duePayment;
        }
      }
      return totalUnpaid;
    });
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
          debugPrint('Error parsing sale ${doc.id}: $e');
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
            debugPrint('Borrow Profit: Sale $saleId, Due: $duePayment, SaleAmount: $saleAmount, Ratio: $unpaidRatio, Profit: $borrowProfit');
          }
        }
      }
      
      debugPrint('Total Borrow Profit: $totalBorrowProfit');
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
          debugPrint('Error parsing sale ${doc.id}: $e');
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
            // Calculate profit proportion for total paid amount
            // This includes initial payment + payments made to cover dues
            final paidRatio = totalPaid / saleAmount;
            final netProfit = sale.netProfit; // Profit after returns
            final realProfit = netProfit * paidRatio;
            totalRealProfit += realProfit;
            debugPrint('Real Profit: Sale $saleId, Total Paid: $totalPaid, SaleAmount: $saleAmount, Ratio: $paidRatio, Profit: $realProfit');
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
            debugPrint('Real Profit (No Seller): Sale ${sale.id}, Amount Paid: ${sale.amountPaid}, Change: ${sale.change}, Amount Received: $amountReceived, Net Total: $netTotal, Profit: $netProfit');
          }
        }
      }
      
      debugPrint('Total Real Profit from Paid: $totalRealProfit');
      return totalRealProfit;
    });
  }

  // Get real profit from paid portions by date range
  // This calculates profit from all paid amounts within the specified date range
  Stream<double> getRealProfitFromPaidStreamByDateRange(DateTime startDate, DateTime endDate) {
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
          debugPrint('Error parsing sale ${doc.id}: $e');
        }
      }
      
      // Group by saleId to sum all payments for each sale (filtered by date)
      final salePayments = <String, double>{};
      final saleAmounts = <String, double>{};
      final salesWithSellerHistory = <String>{};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final saleId = data['saleId'] ?? '';
        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final saleDateStr = data['saleDate'];
        
        // Filter by date range
        if (saleDateStr != null) {
          try {
            final saleDate = DateTime.parse(saleDateStr);
            if (!saleDate.isAfter(startDate.subtract(const Duration(seconds: 1))) ||
                !saleDate.isBefore(endDate.add(const Duration(seconds: 1)))) {
              continue; // Skip if outside date range
            }
          } catch (e) {
            debugPrint('Error parsing saleDate in seller_history ${doc.id}: $e');
            continue;
          }
        } else {
          continue; // Skip if no saleDate
        }
        
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
            // Calculate profit proportion for total paid amount
            // This includes initial payment + payments made to cover dues
            final paidRatio = totalPaid / saleAmount;
            final netProfit = sale.netProfit; // Profit after returns
            final realProfit = netProfit * paidRatio;
            totalRealProfit += realProfit;
            debugPrint('Real Profit (Filtered): Sale $saleId, Total Paid: $totalPaid, SaleAmount: $saleAmount, Ratio: $paidRatio, Profit: $realProfit');
          }
        }
      }
      
      // Also calculate profit from sales without sellers that are fully paid (within date range)
      for (var sale in salesMap.values) {
        // Skip if this sale already has seller history (already counted above)
        if (salesWithSellerHistory.contains(sale.id)) {
          continue;
        }
        
        // Filter by date range
        if (!sale.createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) ||
            !sale.createdAt.isBefore(endDate.add(const Duration(seconds: 1)))) {
          continue; // Skip if outside date range
        }
        
        // Only include sales without sellers that are fully paid
        if (sale.sellerId == null || sale.sellerId!.isEmpty) {
          final netTotal = sale.netTotal; // Total after returns
          final amountReceived = sale.amountPaid - sale.change; // Amount we actually received (excluding change returned)
          if (amountReceived >= netTotal && sale.profit > 0) {
            // Sale is fully paid, add full net profit
            final netProfit = sale.netProfit; // Profit after returns
            totalRealProfit += netProfit;
            debugPrint('Real Profit (No Seller, Filtered): Sale ${sale.id}, Amount Paid: ${sale.amountPaid}, Change: ${sale.change}, Amount Received: $amountReceived, Net Total: $netTotal, Profit: $netProfit');
          }
        }
      }
      
      debugPrint('Total Real Profit from Paid (Filtered): $totalRealProfit');
      return totalRealProfit;
    });
  }

  // Get borrow profit by date range
  // This calculates profit from unpaid portions of sales within the specified date range
  Stream<double> getBorrowProfitStreamByDateRange(DateTime startDate, DateTime endDate) {
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
          debugPrint('Error parsing sale ${doc.id}: $e');
        }
      }
      
      // Calculate profit from unpaid portions (filtered by date)
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final duePayment = (data['duePayment'] ?? 0).toDouble();
        final saleId = data['saleId'] ?? '';
        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
        final saleDateStr = data['saleDate'];
        
        // Filter by date range
        if (saleDateStr != null) {
          try {
            final saleDate = DateTime.parse(saleDateStr);
            if (!saleDate.isAfter(startDate.subtract(const Duration(seconds: 1))) ||
                !saleDate.isBefore(endDate.add(const Duration(seconds: 1)))) {
              continue; // Skip if outside date range
            }
          } catch (e) {
            debugPrint('Error parsing saleDate in seller_history ${doc.id}: $e');
            continue;
          }
        } else {
          continue; // Skip if no saleDate
        }
        
        if (duePayment > 0 && saleId.isNotEmpty && salesMap.containsKey(saleId)) {
          final sale = salesMap[saleId]!;
          if (sale.profit > 0 && saleAmount > 0) {
            // Calculate profit proportion for unpaid portion
            // Use current saleAmount (may have been reduced by returns)
            final unpaidRatio = duePayment / saleAmount;
            final netProfit = sale.netProfit; // Profit after returns
            final borrowProfit = netProfit * unpaidRatio;
            totalBorrowProfit += borrowProfit;
            debugPrint('Borrow Profit (Filtered): Sale $saleId, Due: $duePayment, SaleAmount: $saleAmount, Ratio: $unpaidRatio, Profit: $borrowProfit');
          }
        }
      }
      
      debugPrint('Total Borrow Profit (Filtered): $totalBorrowProfit');
      return totalBorrowProfit;
    });
  }
}

