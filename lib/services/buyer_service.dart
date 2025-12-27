import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/buyer.dart';
import '../models/sale.dart';
import '../models/expense.dart';
import 'buyer_bill_service.dart';
import 'buyer_payment_service.dart';
import 'sales_service.dart';
import 'expense_service.dart';
import 'balance_service.dart';
import 'seller_service.dart';

class BuyerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'buyers';
  final BuyerBillService _billService = BuyerBillService();
  final BuyerPaymentService _paymentService = BuyerPaymentService();
  final SalesService _salesService = SalesService();
  final ExpenseService _expenseService = ExpenseService();
  final BalanceService _balanceService = BalanceService();
  final SellerService _sellerService = SellerService();

  // Get all buyers stream
  Stream<List<Buyer>> getBuyersStream() {
    return _firestore
        .collection(_collection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Buyer.fromMap(doc.data());
      }).toList();
    });
  }

  // Search buyers
  Future<List<Buyer>> searchBuyers(String query) async {
    final snapshot = await _firestore.collection(_collection).get();
    final buyers = snapshot.docs.map((doc) => Buyer.fromMap(doc.data())).toList();
    
    return buyers.where((buyer) {
      final searchQuery = query.toLowerCase();
      return buyer.name.toLowerCase().contains(searchQuery) ||
          (buyer.phone?.toLowerCase().contains(searchQuery) ?? false) ||
          (buyer.location?.toLowerCase().contains(searchQuery) ?? false) ||
          (buyer.shopNo?.toLowerCase().contains(searchQuery) ?? false);
    }).toList();
  }

  // Add buyer
  Future<void> addBuyer(Buyer buyer) async {
    await _firestore.collection(_collection).doc(buyer.id).set(buyer.toMap());
  }

  // Update buyer
  Future<void> updateBuyer(Buyer buyer) async {
    final updatedBuyer = buyer.copyWith(updatedAt: DateTime.now());
    await _firestore
        .collection(_collection)
        .doc(buyer.id)
        .update(updatedBuyer.toMap());
  }

  // Delete buyer
  Future<void> deleteBuyer(String buyerId) async {
    await _firestore.collection(_collection).doc(buyerId).delete();
  }

  // Get buyer by ID
  Future<Buyer?> getBuyerById(String buyerId) async {
    final doc = await _firestore.collection(_collection).doc(buyerId).get();
    if (doc.exists) {
      return Buyer.fromMap(doc.data()!);
    }
    return null;
  }

  // Get real-time due balance for a buyer
  // Calculates: Total bills - Total payments
  // Updates in real-time when bills or payments change
  Stream<double> getDueBalanceStream(String buyerId) {
    return _billService.getBillsByBuyer(buyerId).asyncExpand((bills) {
      if (bills.isEmpty) {
        return Stream.value(0.0);
      }

      // Calculate total bills
      final totalBills = bills.fold<double>(
        0.0,
        (sum, bill) => sum + bill.finalPrice,
      );

      // Get all bill IDs
      final billIds = bills.map((bill) => bill.id).toList();

      // Get all payments for these bills (real-time stream)
      return _paymentService.getAllPaymentsForBuyer(billIds).map((payments) {
        final totalPaid = payments.fold<double>(
          0.0,
          (sum, payment) => sum + payment.amount,
        );

        // Due balance = Total bills - Total payments
        final dueBalance = totalBills - totalPaid;
        return dueBalance > 0 ? dueBalance : 0.0;
      });
    });
  }

  // Get total revenue stream (sum of all buyer bills)
  // Updates in real-time when bills change
  Stream<double> getTotalRevenueStream() {
    return _billService.getBillsStream().map((bills) {
      return bills.fold<double>(
        0.0,
        (sum, bill) => sum + bill.finalPrice,
      );
    });
  }

  // Get total payable payment stream (total due balance across all buyers)
  // Updates in real-time when bills or payments change
  Stream<double> getTotalPayablePaymentStream() {
    return _billService.getBillsStream().asyncExpand((allBills) {
      if (allBills.isEmpty) {
        return Stream.value(0.0);
      }

      // Calculate total bills
      final totalBills = allBills.fold<double>(
        0.0,
        (sum, bill) => sum + bill.finalPrice,
      );

      // Get all bill IDs
      final billIds = allBills.map((bill) => bill.id).toList();

      // Get all payments for all bills (real-time stream)
      return _paymentService.getAllPaymentsForBuyer(billIds).map((payments) {
        final totalPaid = payments.fold<double>(
          0.0,
          (sum, payment) => sum + payment.amount,
        );

        // Total payable = Total bills - Total payments
        final totalPayable = totalBills - totalPaid;
        return totalPayable > 0 ? totalPayable : 0.0;
      });
    });
  }

  // Get total deposit balance stream (total payments received from all buyers)
  // Updates in real-time when payments change
  Stream<double> getTotalDepositBalanceStream() {
    return _billService.getBillsStream().asyncExpand((allBills) {
      if (allBills.isEmpty) {
        return Stream.value(0.0);
      }

      // Get all bill IDs
      final billIds = allBills.map((bill) => bill.id).toList();

      // Get all payments for all bills (real-time stream)
      return _paymentService.getAllPaymentsForBuyer(billIds).map((payments) {
        return payments.fold<double>(
          0.0,
          (sum, payment) => sum + payment.amount,
        );
      });
    });
  }

  // Get total revenue stream (from sales, same calculation as dashboard + balance entries - deposit balance)
  // Calculates: (sum of sale.amountPaid - sale.recoveryBalance - sale.change + sale.creditUsed for non-borrow sales) - expenses - credit reductions + recoveryBalance + balance entries - deposit balance
  // Updates in real-time when sales, expenses, balance entries, credit reductions, or deposit balance change
  Stream<double> getTotalRevenueFromSalesStream() {
    return _salesService.getSalesStream().asyncExpand((sales) {
      return _expenseService.getExpensesStream().asyncExpand((expenses) {
        return _balanceService.getBalanceEntriesStream().asyncExpand((balanceEntries) {
          return _sellerService.getTotalCreditReductionsStream().asyncExpand((creditReductions) {
          return getTotalDepositBalanceStream().map((depositBalance) {
            // Calculate sales revenue (same logic as dashboard)
            double totalRevenue = 0;
            double totalRecoveryBalance = 0;

            for (var sale in sales) {
              // IMPORTANT: Completely exclude borrow payments from revenue calculation
              if (!sale.isBorrowPayment) {
                // Revenue calculation: amountPaid - recoveryBalance - change - cashPortionOfReturn
                // IMPORTANT: 
                // - amountPaid = cash amount customer paid (does NOT include change - change is money returned to customer)
                // - recoveryBalance = amount applied to existing due payments (not revenue for current sale)
                // - change = excess cash returned to customer (MUST be subtracted from revenue)
                // - cashPortionOfReturn = cash portion of returned items (must be subtracted)
                // - creditUsed = credit balance used (NOT included in revenue - it's money owed, not received)
                // Example: Sale total = 4500, customer pays 5000, change = 500
                //   revenue = 5000 - 0 - 500 - 0 = 4500 ✓ (only sale amount, not change)
                // Calculate cash portion of return: returnedAmount * (cashPaid / totalPaid)
                // Where cashPaid = amountPaid - recoveryBalance, totalPaid = cashPaid + creditUsed
                double cashPaid = sale.amountPaid - sale.recoveryBalance;
                double totalPaid = cashPaid + sale.creditUsed;
                double cashPortionOfReturn = 0.0;
                if (sale.returnedAmount > 0 && totalPaid > 0) {
                  // Calculate what portion of the return was originally paid with cash
                  cashPortionOfReturn = sale.returnedAmount * (cashPaid / totalPaid);
                }
                final saleRevenue = sale.amountPaid - sale.recoveryBalance - sale.change - cashPortionOfReturn;
                totalRevenue += saleRevenue;
                totalRecoveryBalance += sale.recoveryBalance;
              }
            }

            // Calculate total expenses
            double totalExpenses = 0;
            for (var expense in expenses) {
              totalExpenses += expense.amount;
            }

            // Calculate net revenue: Revenue - Expenses - Credit Reductions
            // Credit reductions represent money paid to reduce credit balance and should reduce revenue
            final netRevenue = totalRevenue - totalExpenses - creditReductions;

            // Total revenue including recovery balance (money received from sales + recovery from due payments)
            // NOTE: This excludes borrow payments completely - they are NOT included in revenue
            final totalRevenueWithRecovery = netRevenue + totalRecoveryBalance;

            // Add balance entries to total revenue
            final totalBalanceEntries = balanceEntries.fold<double>(
              0.0,
              (sum, entry) => sum + entry.amount,
            );

            // Subtract deposit balance from total revenue
            // When buyers make payments (deposit balance increases), it reduces total revenue
            final finalRevenue = totalRevenueWithRecovery + totalBalanceEntries - depositBalance;

            return finalRevenue;
            });
          });
        });
      });
    });
  }
}
