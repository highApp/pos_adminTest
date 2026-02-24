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
import 'reset_data_service.dart';

class BuyerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'buyers';
  final BuyerBillService _billService = BuyerBillService();
  final BuyerPaymentService _paymentService = BuyerPaymentService();
  final SalesService _salesService = SalesService();
  final ExpenseService _expenseService = ExpenseService();
  final BalanceService _balanceService = BalanceService();
  final SellerService _sellerService = SellerService();
  final ResetDataService _resetDataService = ResetDataService();

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

  /// Deposit balance (sum of payments) on or after [fromDate]. Used when financial reset is set.
  Stream<double> _getDepositBalanceFromDateStream(DateTime fromDate) {
    final cutoff = fromDate.subtract(const Duration(seconds: 1));
    return _billService.getBillsStream().asyncExpand((bills) {
      if (bills.isEmpty) return Stream.value(0.0);
      final ids = bills.map((b) => b.id).toList();
      return _paymentService.getAllPaymentsForBuyer(ids).map((payments) {
        return payments
            .where((p) => !p.paymentDate.isBefore(cutoff))
            .fold<double>(0.0, (s, p) => s + p.amount);
      });
    });
  }

  // Get total revenue stream (from sales, same calculation as dashboard + balance entries - deposit balance)
  // Respects financial reset date: only counts sales, expenses, balance entries, credit reductions, and deposit balance on or after reset date.
  Stream<double> getTotalRevenueFromSalesStream() {
    return _resetDataService.getFinancialResetDateStream().asyncExpand((resetDate) {
      return _salesService.getSalesStream().asyncExpand((sales) {
        return _expenseService.getExpensesStream().asyncExpand((expenses) {
          return _balanceService.getBalanceEntriesStream().asyncExpand((balanceEntries) {
            final creditReductionsStream = resetDate != null
                ? _sellerService.getTotalCreditReductionsFromDateStream(resetDate)
                : _sellerService.getTotalCreditReductionsStream();
            return creditReductionsStream.asyncExpand((creditReductions) {
              final depositStream = resetDate != null
                  ? _getDepositBalanceFromDateStream(resetDate)
                  : getTotalDepositBalanceStream();
              return depositStream.map((depositBalance) {
                final cutoff = resetDate?.subtract(const Duration(seconds: 1));
                final filteredSales = cutoff != null
                    ? sales.where((s) => !s.createdAt.isBefore(cutoff)).toList()
                    : sales;
                final filteredExpenses = cutoff != null
                    ? expenses.where((e) => !e.createdAt.isBefore(cutoff)).toList()
                    : expenses;
                final filteredBalanceEntries = cutoff != null
                    ? balanceEntries.where((e) => !e.date.isBefore(cutoff)).toList()
                    : balanceEntries;

                double totalRevenue = 0;
                double totalRecoveryBalance = 0;
                for (var sale in filteredSales) {
                  if (!sale.isBorrowPayment) {
                    double cashPaid = sale.amountPaid - sale.recoveryBalance;
                    double totalPaid = cashPaid + sale.creditUsed;
                    double cashPortionOfReturn = 0.0;
                    if (sale.returnedAmount > 0 && totalPaid > 0) {
                      cashPortionOfReturn = sale.returnedAmount * (cashPaid / totalPaid);
                    }
                    final saleRevenue = sale.amountPaid - sale.recoveryBalance - sale.change - cashPortionOfReturn;
                    totalRevenue += saleRevenue;
                    totalRecoveryBalance += sale.recoveryBalance;
                  }
                }

                double totalExpenses = 0;
                for (var expense in filteredExpenses) {
                  totalExpenses += expense.amount;
                }

                final netRevenue = totalRevenue - totalExpenses - creditReductions;
                final totalRevenueWithRecovery = netRevenue + totalRecoveryBalance;
                final totalBalanceEntries = filteredBalanceEntries.fold<double>(
                  0.0,
                  (sum, entry) => sum + entry.amount,
                );
                final finalRevenue = totalRevenueWithRecovery + totalBalanceEntries - depositBalance;
                return finalRevenue;
              });
            });
          });
        });
      });
    });
  }

  /// Total profit from sales (sum of sale.netProfit for non-borrow sales) minus expenses.
  /// Respects financial reset date. Use for a separate "Profit" metric so it is not mixed with Total Revenue.
  Stream<double> getTotalProfitFromSalesStream() {
    return _resetDataService.getFinancialResetDateStream().asyncExpand((resetDate) {
      return _salesService.getSalesStream().asyncExpand((sales) {
        return _expenseService.getExpensesStream().map((expenses) {
          final cutoff = resetDate?.subtract(const Duration(seconds: 1));
          final filteredSales = cutoff != null
              ? sales.where((s) => !s.createdAt.isBefore(cutoff)).toList()
              : sales;
          final filteredExpenses = cutoff != null
              ? expenses.where((e) => !e.createdAt.isBefore(cutoff)).toList()
              : expenses;

          double totalProfit = 0;
          for (var sale in filteredSales) {
            if (!sale.isBorrowPayment) {
              totalProfit += sale.netProfit;
            }
          }
          double totalExpenses = 0;
          for (var expense in filteredExpenses) {
            totalExpenses += expense.amount;
          }
          return totalProfit - totalExpenses;
        });
      });
    });
  }
}
