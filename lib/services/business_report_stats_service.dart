import '../models/business_report_stats.dart';
import '../models/borrow.dart';
import '../models/seller_order.dart';
import '../models/borrow_totals_breakdown.dart';
import '../models/seller_borrow_profit_summary.dart';
import '../models/seller_real_profit_summary.dart';
import '../services/sales_service.dart';
import '../services/expense_service.dart';
import '../services/borrow_service.dart';
import '../services/seller_service.dart';
import '../services/seller_order_service.dart';
import '../services/reset_data_service.dart';
import '../services/balance_service.dart';
import '../services/buyer_payment_service.dart';

/// Business Report card stats aligned to `DashboardScreen` math.
///
/// Note: This service intentionally mirrors the logic from
/// `DashboardScreen._calculateCombinedStats` but returns only the values
/// required for the report card UI.
class BusinessReportStatsService {
  final salesService = SalesService();
  final expenseService = ExpenseService();
  final borrowService = BorrowService();
  final sellerService = SellerService();
  final sellerOrderService = SellerOrderService();
  final resetDataService = ResetDataService();
  final balanceService = BalanceService();
  final buyerPaymentService = BuyerPaymentService();

  Future<BusinessReportStats> calculateForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // Matches DashboardScreen semantics:
    // "Reset Revenue & Credit" only starts counting from reset date.
    final resetDate = await resetDataService.getFinancialResetDate();
    final effectiveStartDate = (resetDate != null && resetDate.isAfter(startDate))
        ? resetDate
        : startDate;

    // Load live lists in the selected range (same date semantics as dashboard streams).
    //
    // Dashboard uses:
    // - sales.createdAt for POS
    // - expenses.createdAt for expenses
    // - borrows.createdAt for borrow book
    // - seller_orders.completedAt for wholesale orders
    // - balance_entries.date for manual balance revenue
    //
    // For seller_history we rely on dashboard helper streams that already align
    // profit + unpaid/recovery semantics.
    final startPad = effectiveStartDate.subtract(const Duration(seconds: 1));
    final endPad = endDate.add(const Duration(seconds: 1));

    final sales = await salesService.getSalesByDateRange(startPad, endPad).first;
    final expenses = await expenseService.getExpensesByDateRange(startPad, endPad).first;
    final borrows = await borrowService.getBorrowsByDateRange(startPad, endPad).first;

    final sellerOrdersAll = await sellerOrderService.getAllOrders().first;
    final balanceEntriesAll = await balanceService.getBalanceEntriesStream().first;

    final buyerPaidTotal = await buyerPaymentService
        .getTotalPaidByDateRangeStream(effectiveStartDate, endDate)
        .first;

    final unpaidTotals = await sellerService
        .getUnpaidSalesDashboardTotalsStream(effectiveStartDate, endDate)
        .first;

    final profitTotals = await sellerService
        .getDashboardSellerProfitTotalsStream(effectiveStartDate, endDate)
        .first;

    // Credit reductions affect net revenue.
    final periodCreditReductions = await sellerService
        .getTotalCreditReductionsByDateRange(effectiveStartDate, endDate);

    // Filter wholesale orders by date range (matches dashboard).
    final filteredSellerOrders = sellerOrdersAll.where((order) {
      return order.status == OrderStatus.completed &&
          order.completedAt != null &&
          order.completedAt!.isAfter(
              effectiveStartDate.subtract(const Duration(seconds: 1))) &&
          order.completedAt!.isBefore(endDate.add(const Duration(seconds: 1)));
    }).toList();

    // Filter balance entries by date range (matches dashboard day semantics).
    final filteredBalanceEntries = balanceEntriesAll.where((entry) {
      final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
      return !entryDate.isBefore(effectiveStartDate) &&
          !entryDate.isAfter(DateTime(endDate.year, endDate.month, endDate.day));
    }).toList();

    final totalBalanceEntries = filteredBalanceEntries.fold<double>(
      0.0,
      (sum, e) => sum + e.amount,
    );

    // ---- Compute recovery, revenue, expenses, profits ----
    double totalRevenueCashAndCreditExcluded = 0.0; // sum of sale.dashboardPosCashRevenue
    double totalRecoveryBalance = 0.0; // recovery from sales only
    double totalExpenses = 0.0;
    double totalCreditAdded = 0.0; // manual overpayment credit added from manual payment sales
    double borrowProfitPending = profitTotals.borrowProfit;

    for (final expense in expenses) {
      totalExpenses += expense.amount;
    }

    // Wholesale orders revenue & profit.
    double wholesaleRevenue = 0.0;
    double wholesaleProfit = 0.0;
    for (final order in filteredSellerOrders) {
      wholesaleRevenue += order.total;
      wholesaleProfit += order.profit;
    }

    // IMPORTANT: Borrow payments are excluded from revenue/profit calculation.
    for (final sale in sales) {
      if (sale.isBorrowPayment) {
        // borrow payments are not revenue; profit is handled by seller_history profitTotals.
        continue;
      }

      // Dashboard's revenue math for POS:
      // revenueCash = sale.dashboardPosCashRevenue
      totalRevenueCashAndCreditExcluded += sale.dashboardPosCashRevenue;

      // Recovery (money applied to existing due payments) net of returns.
      final netRecoveryAfterReturns =
          (sale.recoveryBalance - sale.returnedAmount).clamp(0.0, double.infinity);
      totalRecoveryBalance += netRecoveryAfterReturns;

      // Credit added from manual overpayments (when payment > due amount, total=0 manual sales).
      final isManualPaymentSale = sale.total == 0 &&
          (sale.customerName?.startsWith('Manual Payment') ?? false);
      if (isManualPaymentSale && sale.amountPaid > sale.recoveryBalance) {
        totalCreditAdded += sale.amountPaid - sale.recoveryBalance;
      }
    }

    // Net revenue after expenses and credit reductions.
    final grossRevenue = totalRevenueCashAndCreditExcluded;
    final netRevenue = grossRevenue - totalExpenses - periodCreditReductions;

    // Total revenue including recovery + wholesale + credit added + manual balance entries.
    final totalRevenueWithRecovery =
        netRevenue + totalRecoveryBalance + totalCreditAdded + wholesaleRevenue + totalBalanceEntries;

    // Total borrow (report): gross outstanding borrow in selected range.
    // Recovery is shown separately in `totalRecovery`.
    final grossBorrowHeadline = unpaidTotals.periodOutstandingFromHistory + _safeSumBorrowedAmount(borrows);
    final totalBorrowHeadline = grossBorrowHeadline;

    // Total profit with borrow:
    // Dashboard: totalProfitWithBorrow = netProfit + borrowProfit (where netProfit = realProfit - expenses + wholesaleProfit)
    // We already have `profitTotals.realProfit` = realProfit (paid portions) and `borrowProfitPending`.
    final netProfit = profitTotals.realProfit - totalExpenses + wholesaleProfit;
    final totalProfitWithBorrow = netProfit + borrowProfitPending;

    // Assemble model.
    return BusinessReportStats(
      totalRevenue: totalRevenueWithRecovery,
      totalBorrow: totalBorrowHeadline,
      totalExpense: totalExpenses,
      totalPaid: buyerPaidTotal,
      totalRecovery: totalRecoveryBalance,
      totalProfitReal: netProfit,
      borrowProfitPending: borrowProfitPending,
      totalProfitWithBorrow: totalProfitWithBorrow,
    );
  }

  /// Utility: dashboard uses borrow list where `!borrow.isPaid` and sums by type.
  double _safeSumBorrowedAmount(List<Borrow> borrows) {
    double totalBorrowed = 0.0;
    for (final borrow in borrows) {
      if (!borrow.isPaid && borrow.type == 'borrowed') {
        totalBorrowed += borrow.amount;
      }
    }
    return totalBorrowed;
  }

  /// Returns the list of sellers that contribute to "Borrow Profit (Pending)"
  /// for the selected date filter.
  Future<List<SellerBorrowProfitSummary>> getBorrowProfitPendingBySellerForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // Matches `calculateForRange` reset semantics.
    final resetDate = await resetDataService.getFinancialResetDate();
    final effectiveStartDate = (resetDate != null && resetDate.isAfter(startDate))
        ? resetDate
        : startDate;

    return sellerService.getBorrowProfitPendingBySellerForDateRange(
      effectiveStartDate,
      endDate,
    );
  }

  Future<List<SellerRealProfitSummary>> getRealProfitBySellerForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final resetDate = await resetDataService.getFinancialResetDate();
    final effectiveStartDate = (resetDate != null && resetDate.isAfter(startDate))
        ? resetDate
        : startDate;

    return sellerService.getRealProfitBySellerForDateRange(
      effectiveStartDate,
      endDate,
    );
  }

  /// Explains why "Total Borrow" can be `0` by showing:
  /// - seller due split: manual vs POS (remaining duePayment in seller_history range)
  /// - borrow book: unpaid `type == 'borrowed'`
  /// - repayments: recovery applied to old dues in the selected sales period
  ///
  /// dashboard math:
  /// netBorrow = (sellerDueTotal + borrowBookBorrowed - repaymentsInPeriod).clamp(>=0)
  Future<BorrowTotalsBreakdown> getBorrowTotalsBreakdownForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final resetDate = await resetDataService.getFinancialResetDate();
    final effectiveStartDate = (resetDate != null && resetDate.isAfter(startDate))
        ? resetDate
        : startDate;

    final startPad = effectiveStartDate.subtract(const Duration(seconds: 1));
    final endPad = endDate.add(const Duration(seconds: 1));

    final sellers = await sellerService.getBorrowDueSplitBySellerForDateRange(
      effectiveStartDate,
      endDate,
    );

    double sellerDueManual = 0.0;
    double sellerDuePos = 0.0;
    for (final s in sellers) {
      sellerDueManual += s.manualDue;
      sellerDuePos += s.posDue;
    }
    final sellerDueTotal = sellerDueManual + sellerDuePos;

    final borrowBookBorrowed = await borrowService.getTotalBorrowedByDateRange(
      startPad,
      endPad,
    );

    final sales = await salesService.getSalesByDateRange(startPad, endPad).first;
    double repaymentsInPeriod = 0.0;
    for (final sale in sales) {
      if (sale.isBorrowPayment) continue;
      final netRecoveryAfterReturns =
          (sale.recoveryBalance - sale.returnedAmount).clamp(0.0, double.infinity);
      if (netRecoveryAfterReturns > 0) {
        repaymentsInPeriod += netRecoveryAfterReturns;
      }
    }

    final netBorrow = (sellerDueTotal + borrowBookBorrowed - repaymentsInPeriod)
        .clamp(0.0, double.infinity);

    return BorrowTotalsBreakdown(
      sellerDueManual: sellerDueManual,
      sellerDuePos: sellerDuePos,
      sellerDueTotal: sellerDueTotal,
      borrowBookBorrowed: borrowBookBorrowed,
      repaymentsInPeriod: repaymentsInPeriod,
      netBorrow: netBorrow,
      sellers: sellers,
    );
  }
}

