import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/sale.dart';
import 'seller_service.dart';

class SalesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'sales';

  // Add new sale
  Future<void> addSale(Sale sale) async {
    await _firestore.collection(_collection).doc(sale.id).set(sale.toMap());
  }

  // Get all sales stream
  Stream<List<Sale>> getSalesStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Sale.fromMap(doc.data());
      }).toList();
    });
  }

  // Get sales by date range
  Stream<List<Sale>> getSalesByDateRange(DateTime startDate, DateTime endDate) {
    return _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Sale.fromMap(doc.data());
      }).toList();
    });
  }

  // Get today's sales
  Stream<List<Sale>> getTodaySales() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    return getSalesByDateRange(startOfDay, endOfDay);
  }

  // Get sales statistics
  Future<Map<String, dynamic>> getSalesStats() async {
    final snapshot = await _firestore.collection(_collection).get();
    final sales = snapshot.docs.map((doc) => Sale.fromMap(doc.data())).toList();

    double totalRevenue = 0;
    int totalTransactions = 0; // Count only non-borrow transactions

    for (var sale in sales) {
      // Skip borrow payments from revenue and transaction count
      if (!sale.isBorrowPayment) {
        totalRevenue += sale.total;
        totalTransactions++;
      }
    }

    return {
      'totalRevenue': totalRevenue,
      'totalTransactions': totalTransactions,
      'averageTransaction': totalTransactions > 0 ? totalRevenue / totalTransactions : 0,
    };
  }

  // Get today's statistics
  Future<Map<String, dynamic>> getTodayStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return getStatsByDateRange(startOfDay, endOfDay);
  }

  // Get statistics by date range
  Future<Map<String, dynamic>> getStatsByDateRange(DateTime startDate, DateTime endDate) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .get();

    final sales = snapshot.docs.map((doc) => Sale.fromMap(doc.data())).toList();

    double grossRevenue = 0; // Total sales before returns
    double totalProfit = 0;
    double totalReturned = 0; // Returns from actual sales only
    double totalRecoveryBalance = 0; // Total recovery balance from all sales
    int totalTransactions = 0; // Count only actual sales (exclude borrow payments)

    for (var sale in sales) {
      // IMPORTANT: Skip borrow payments from revenue, profit, and transaction count
      // Borrow payments are NOT sales - they're tracked separately in recovery balance only
      // Example: Revenue 5000 + Borrow Payment 5000 = Revenue still 5000 (not 10000)
      if (!sale.isBorrowPayment) {
        grossRevenue += sale.total; // Gross revenue (before returns)
        totalReturned += sale.returnedAmount; // Track returns from actual sales only
        totalProfit += sale.netProfit; // Use net profit (after returns)
        totalTransactions++; // Count only actual sales transactions
      }
      totalRecoveryBalance += sale.recoveryBalance; // Track recovery balance separately (includes borrow payments)
    }

    // Calculate net revenue: Gross Revenue - Returns
    // This explicitly subtracts returns from revenue
    final netRevenue = grossRevenue - totalReturned;

    // Revenue is sales only (after returns). Recovery balance is shown separately on the dashboard.
    // Total money received = totalRevenue + totalRecoveryBalance

    return {
      'totalRevenue': netRevenue, // Net revenue after subtracting returns
      'totalProfit': totalProfit,
      'totalReturned': totalReturned,
      'totalRecoveryBalance': totalRecoveryBalance,
      'totalTransactions': totalTransactions,
      'averageTransaction': totalTransactions > 0 ? netRevenue / totalTransactions : 0,
    };
  }

  // Delete sale (if needed)
  Future<void> deleteSale(String saleId) async {
    await _firestore.collection(_collection).doc(saleId).delete();
  }

  // Process sale return
  Future<void> processSaleReturn(Sale sale, {double? previousReturnedAmount}) async {
    // IMPORTANT: Always fetch the original sale from database FIRST to get the true original creditUsed
    // The passed sale object might have been modified, so we need the original from database
    double returnAmount = 0.0;
    double originalCreditUsed = 0.0;
    
    try {
      // Fetch the original sale from database to get the true original creditUsed
      final doc = await _firestore.collection(_collection).doc(sale.id).get();
      if (doc.exists) {
        final originalSale = Sale.fromMap(doc.data()!);
        // Always use the original creditUsed from database (this is the true original value)
        originalCreditUsed = originalSale.creditUsed;
        
        // Calculate return amount
    if (previousReturnedAmount != null) {
      // Calculate the new return amount (difference)
      returnAmount = sale.returnedAmount - previousReturnedAmount;
    } else {
          // Calculate return amount from difference
          returnAmount = sale.returnedAmount - originalSale.returnedAmount;
          }
        } else {
          // New sale, all returnedAmount is new return
          returnAmount = sale.returnedAmount;
        // For new sale, use creditUsed from passed sale object
        originalCreditUsed = sale.creditUsed;
        }
      } catch (e) {
      debugPrint('Error fetching original sale for return calculation: $e');
      // Fallback: use values from passed sale object
        returnAmount = sale.returnedAmount;
      originalCreditUsed = sale.creditUsed;
    }
    
    // Update the sale
    await _firestore
        .collection(_collection)
        .doc(sale.id)
        .update(sale.toMap());
    
    // If there's a return amount and the sale has a seller, update seller history and restore credit
    if (returnAmount > 0 && sale.sellerId != null) {
      try {
        final sellerService = SellerService();
        
        // Update seller history (reduces due payment)
        await sellerService.updateSellerHistoryForReturn(sale.id, returnAmount);
        debugPrint('✓ Seller history updated for return: Rs. $returnAmount');
        
        // Restore credit balance if credit was used in the original sale
        if (originalCreditUsed > 0 && sale.total > 0) {
          // Calculate proportion of credit to restore based on return amount
          // Example: If sale was Rs. 1000 with Rs. 200 credit, and return is Rs. 300
          // Then restore: (300 / 1000) * 200 = Rs. 60 credit
          final creditRestoreRatio = returnAmount / sale.total;
          final creditToRestore = originalCreditUsed * creditRestoreRatio;
          
          if (creditToRestore > 0) {
            await sellerService.addCreditBalance(
              sale.sellerId!,
              creditToRestore,
              description: 'Credit restored from item return',
            );
            debugPrint('✓ Credit balance restored: Rs. $creditToRestore');
            debugPrint('  - Original Credit Used: Rs. $originalCreditUsed');
            debugPrint('  - Return Amount: Rs. $returnAmount');
            debugPrint('  - Sale Total: Rs. ${sale.total}');
            debugPrint('  - Restore Ratio: ${(creditRestoreRatio * 100).toStringAsFixed(2)}%');
          }
        }
      } catch (e) {
        debugPrint('Error updating seller history/credit for return: $e');
        // Don't throw - sale update succeeded, seller history update failure shouldn't block return
      }
    }
  }

  // Get total unpaid sales amount by date range
  // Unpaid = sales where amountPaid < (total - returnedAmount)
  // Excludes borrow payments (they're tracked separately)
  Future<double> getTotalUnpaidSalesByDateRange(DateTime startDate, DateTime endDate) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .get();

    double totalUnpaid = 0.0;
    for (var doc in snapshot.docs) {
      final sale = Sale.fromMap(doc.data());
      // Skip borrow payments (they're not sales)
      if (sale.isBorrowPayment) continue;
      
      final netTotal = sale.netTotal; // total - returnedAmount
      final unpaidAmount = netTotal - sale.amountPaid;
      if (unpaidAmount > 0) {
        totalUnpaid += unpaidAmount;
      }
    }

    return totalUnpaid;
  }
}

