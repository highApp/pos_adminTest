import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/sales_service.dart';
import '../services/product_service.dart';
import '../services/expense_service.dart';
import '../services/borrow_service.dart';
import '../services/seller_service.dart';
import '../services/seller_order_service.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/expense.dart';
import '../models/borrow.dart';
import '../models/seller_order.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final salesService = SalesService();
  final productService = ProductService();
  final expenseService = ExpenseService();
  final borrowService = BorrowService();
  final sellerService = SellerService();
  final sellerOrderService = SellerOrderService();
  int? _selectedDays = 0; // 0 = Today, null = custom date range
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _showProfit = false; // Hide profit by default

  void _toggleProfitVisibility() {
    if (_showProfit) {
      // If already showing, just hide it
      setState(() {
        _showProfit = false;
      });
    } else {
      // If hidden, ask for password
      _showPasswordDialog();
    }
  }

  void _showPasswordDialog() {
    final TextEditingController passwordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.teal.shade700),
            const SizedBox(width: 12),
            const Text('Enter Password'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter password to view profit information',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.password),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.help_outline),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Contact administrator for password'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
              onSubmitted: (value) {
                _verifyPassword(value, passwordController);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _verifyPassword(passwordController.text, passwordController);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
            label: const Text('Submit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _verifyPassword(String password, TextEditingController controller) {
    const String correctPassword = '5202';
    
    if (password == correctPassword) {
      setState(() {
        _showProfit = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Profit information unlocked'),
            ],
          ),
          backgroundColor: Colors.teal,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Text('Incorrect password'),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    controller.clear();
  }

  void _showCustomDatePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      helpText: 'Select Date Range',
      cancelText: 'Cancel',
      confirmText: 'Apply',
    );

    if (picked != null) {
      setState(() {
        _customStartDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _customEndDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        _selectedDays = null; // Set to null to indicate custom range
      });
    }
  }

  DateTime _getStartDate() {
    final now = DateTime.now();
    if (_selectedDays == null) {
      // Custom date range
      return _customStartDate ?? now.subtract(const Duration(days: 7));
    } else if (_selectedDays == 0) {
      // Today
      return DateTime(now.year, now.month, now.day);
    } else {
      // Last N days
      return now.subtract(Duration(days: _selectedDays!));
    }
  }

  DateTime _getEndDate() {
    final now = DateTime.now();
    if (_selectedDays == null) {
      // Custom date range
      return _customEndDate ?? now;
    } else if (_selectedDays == 0) {
      // Today
      return DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else {
      // Last N days (up to now)
      return now;
    }
  }

  String _getDateRangeLabel() {
    if (_selectedDays == null) {
      if (_customStartDate != null && _customEndDate != null) {
        return '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd').format(_customEndDate!)}';
      }
      return 'Custom Range';
    } else if (_selectedDays == 0) {
      return 'Today';
    } else {
      return 'Last $_selectedDays Days';
    }
  }

  // Calculate combined stats from stream data (for real-time updates)
  Map<String, dynamic> _calculateCombinedStats(
    List<Sale> sales,
    List<Expense> expenses,
    List<Borrow> borrows,
    List<SellerOrder> sellerOrders,
    double totalUnpaidSales,
    double borrowProfit,
    double realProfitFromPaid,
    double totalCreditReductions,
  ) {
    try {
      final startDate = _getStartDate();
      final endDate = _getEndDate();
      
      // Filter sales by date range
      final filteredSales = sales.where((sale) {
        return sale.createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
               sale.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();
      
      // Filter expenses by date range
      final filteredExpenses = expenses.where((expense) {
        return expense.createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
               expense.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();
      
      // Filter borrows by date range
      final filteredBorrows = borrows.where((borrow) {
        return borrow.createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
               borrow.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();
      
      // Filter completed seller orders by date range
      final filteredSellerOrders = sellerOrders.where((order) {
        return order.status == OrderStatus.completed &&
               order.completedAt != null &&
               order.completedAt!.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
               order.completedAt!.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();
      
      // If "Today" is selected, use all seller orders for revenue calculation
      // Otherwise, use filtered orders
      final ordersForRevenue = (_selectedDays == 0) 
          ? sellerOrders.where((order) => order.status == OrderStatus.completed && order.completedAt != null).toList()
          : filteredSellerOrders;
      
      // Calculate wholesale orders revenue and profit
      double wholesaleRevenue = 0;
      double wholesaleProfit = 0;
      int wholesaleTransactions = filteredSellerOrders.length;
      
      for (var order in ordersForRevenue) {
        wholesaleRevenue += order.total;
        wholesaleProfit += order.profit;
      }
      
      // Calculate sales stats
      double totalRevenue = 0;
      double todayRevenue = 0; // Today's revenue only (for breakdown when "Today" is selected)
      double totalReturned = 0;
      double totalRecoveryBalance = 0; // Only recovery from actual sales, not borrow payments
      double todayRecoveryBalance = 0; // Today's recovery balance only (for breakdown when "Today" is selected)
      double totalCreditUsed = 0; // Total credit balance used from sellers
      double todayCreditUsed = 0; // Today's credit used only (for breakdown when "Today" is selected)
      double todayBorrowPayments = 0; // Sum of borrow payments made today
      int totalTransactions = 0;
      
      // Track sales for profit calculation
      final salesMap = <String, Sale>{};
      
      // Get today's date range for borrow payments calculation
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      // If "Today" is selected, calculate overall total revenue from all sales (not filtered)
      // Otherwise, use filtered sales
      final salesForRevenue = (_selectedDays == 0) ? sales : filteredSales;
      
      for (var sale in salesForRevenue) {
        // IMPORTANT: Completely exclude borrow payments from revenue calculation
        // Borrow payments should NOT affect revenue at all
        if (!sale.isBorrowPayment) {
          // Only count actual sales (not borrow payments)
          // Revenue calculation:
          // Revenue = amountPaid - recoveryBalance - change - cashPortionOfReturn
          // 
          // IMPORTANT: 
          // - amountPaid = cash amount customer paid (does NOT include change - change is money returned to customer)
          // - recoveryBalance = amount applied to existing due payments (not revenue for current sale)
          // - change = excess cash returned to customer (must be subtracted from revenue)
          // - cashPortionOfReturn = cash portion of returned items (must be subtracted from revenue)
          // - creditUsed = credit balance used (NOT included in revenue - it's money owed, not received)
          //
          // Example 1: Sale total = 4500, customer pays 5000 cash, no seller, no returns
          //   amountPaid = 5000, recoveryBalance = 0, change = 500, creditUsed = 0, returnedAmount = 0
          //   revenue = 5000 - 0 - 500 - 0 = 4500 ✓ (correct - only the sale amount, not the change)
          //
          // Example 2: Sale total = 1000, customer pays 1000 cash, 250 credit, returns 250 worth
          //   amountPaid = 1000, recoveryBalance = 0, change = 0, creditUsed = 250, returnedAmount = 250, total = 1250
          //   cashPaid = 1000, totalPaid = 1250, cashPortionOfReturn = 250 * (1000/1250) = 200
          //   revenue = 1000 - 0 - 0 - 200 = 800 ✓ (only cash portion of return reduces revenue)
          //
          // Example 3: Sale total = 1250, customer pays 0 cash, 1250 credit, returns 250 worth
          //   amountPaid = 0, recoveryBalance = 0, change = 0, creditUsed = 1250, returnedAmount = 250
          //   cashPaid = 0, totalPaid = 1250, cashPortionOfReturn = 250 * (0/1250) = 0
          //   revenue = 0 - 0 - 0 - 0 = 0 ✓ (no cash received, so no revenue to reduce)
          double cashPaid = sale.amountPaid - sale.recoveryBalance;
          double totalPaid = cashPaid + sale.creditUsed;
          double cashPortionOfReturn = 0.0;
          if (sale.returnedAmount > 0 && totalPaid > 0) {
            // Calculate what portion of the return was originally paid with cash
            cashPortionOfReturn = sale.returnedAmount * (cashPaid / totalPaid);
          }
          final saleRevenue = sale.amountPaid - sale.recoveryBalance - sale.change - cashPortionOfReturn;
          totalRevenue += saleRevenue; // Revenue = cash payment only, minus cash portion of returns (credit portion doesn't affect revenue)
          
          // Calculate net credit used (original credit used minus restored credit from returns)
          // When items are returned, credit is restored proportionally
          // Example: If sale.total = 1000, creditUsed = 200, returnedAmount = 300
          // Then restored credit = (300 / 1000) * 200 = 60
          // Net credit used = 200 - 60 = 140
          double netCreditUsed = sale.creditUsed;
          if (sale.returnedAmount > 0 && sale.total > 0 && sale.creditUsed > 0) {
            final creditRestoreRatio = sale.returnedAmount / sale.total;
            final creditRestored = sale.creditUsed * creditRestoreRatio;
            netCreditUsed = sale.creditUsed - creditRestored;
            debugPrint('Sale ${sale.id}: Credit Used = ${sale.creditUsed}, Returned = ${sale.returnedAmount}, Restored Credit = $creditRestored, Net Credit Used = $netCreditUsed');
          }
          
          // If "Today" is selected, also calculate today's revenue separately for breakdown
          if (_selectedDays == 0 && 
              sale.createdAt.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
              sale.createdAt.isBefore(todayEnd.add(const Duration(seconds: 1)))) {
            todayRevenue += saleRevenue;
            todayRecoveryBalance += sale.recoveryBalance;
            todayCreditUsed += netCreditUsed; // Use net credit used (after returns)
          }
          
          // Store sale for profit calculation from seller_history
          salesMap[sale.id] = sale;
          
          totalTransactions++;
          // Only include recovery balance from actual sales (not borrow payments)
          // Recovery balance from sales represents money received from paying off due payments
          // This excludes borrow payments which have isBorrowPayment = true
          totalRecoveryBalance += sale.recoveryBalance;
          // Track net credit balance used (after accounting for returns)
          totalCreditUsed += netCreditUsed;
        } else {
          // Skip borrow payments completely - they should not affect revenue
          // Borrow payments are tracked separately in the borrow section only
          debugPrint('Skipping borrow payment from revenue: ${sale.id}, amount: ${sale.total}');
          
          // Calculate today's borrow payments sum - only count if sale was created today
          if (sale.isBorrowPayment && 
              sale.createdAt.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
              sale.createdAt.isBefore(todayEnd.add(const Duration(seconds: 1)))) {
            todayBorrowPayments += sale.amountPaid;
          }
        }
        // Count returns from all sales (including borrow payments if any)
        totalReturned += sale.returnedAmount;
      }
      
      // Real profit from seller_history (includes payments made to cover dues)
      // This is calculated from the stream filtered by date range and passed as parameter
      // It includes profit from all paid amounts (initial payment + payments to cover dues) within the selected date range
      double totalRealProfit = realProfitFromPaid;
      
      // Explicitly calculate profit lost from returns and subtract it
      // netProfit already does this, but we ensure it's clear:
      // If sale.profit = 200, sale.total = 1000, sale.returnedAmount = 200
      // Then profit lost = 200 * (200/1000) = 40
      // netProfit = 200 - 40 = 160 (which is what sale.netProfit returns)
      // So the calculation is already correct via sale.netProfit
      
      // Calculate expenses
      double totalExpenses = 0;
      // Calculate total expenses from filtered expenses (for profit calculation)
      for (var expense in filteredExpenses) {
        totalExpenses += expense.amount;
      }
      
      // totalCreditReductions is passed as parameter (calculated from stream)
      
      // Calculate borrows
      double totalBorrowed = 0;
      double totalLent = 0;
      for (var borrow in filteredBorrows) {
        if (!borrow.isPaid) {
          if (borrow.type == 'borrowed') {
            totalBorrowed += borrow.amount;
          } else if (borrow.type == 'lent') {
            totalLent += borrow.amount;
          }
        }
      }
      final netBorrow = totalBorrowed - totalLent;
      
      // Calculate net profit: Real profit (from paid portions including payments to cover dues) - Expenses + Wholesale profit
      // This explicitly subtracts expenses from profit and adds wholesale profit
      // Example: Real profit = 1000, Expenses = 200, Wholesale profit = 300, Net Profit = 1100
      final netProfit = totalRealProfit - totalExpenses + wholesaleProfit;
      
      // Calculate total profit including borrow profit
      // Borrow profit is profit from unpaid portions of sales
      // When payments are made, borrow profit transfers to real profit
      final totalProfitWithBorrow = netProfit + borrowProfit;
      
      // Revenue already accounts for returns (uses netTotal), now also subtract expenses and add wholesale revenue
      final grossRevenue = totalRevenue; // Sales revenue after returns (netTotal)
      
      // Always subtract credit reductions from revenue (they represent money paid to reduce credit)
      // If "Today" is selected, show overall revenue but still subtract all credit reductions
      // Otherwise, subtract expenses and credit reductions for the date range
      final netRevenue = (_selectedDays == 0) 
          ? grossRevenue - totalCreditReductions  // Overall revenue (all time) - subtract credit reductions only
          : grossRevenue - totalExpenses - totalCreditReductions; // Revenue after returns, expenses, and credit reductions for date range
      
      // Total revenue including recovery balance AND wholesale orders
      // NOTE: This excludes borrow payments completely - they are NOT included in revenue
      // Borrow payments are tracked separately in the borrow section only
      final totalRevenueWithRecovery = netRevenue + totalRecoveryBalance + wholesaleRevenue;
      
      debugPrint('=== REVENUE CALCULATION ===');
      debugPrint('Date Filter: ${_selectedDays == 0 ? "Today (showing overall revenue)" : _getDateRangeLabel()}');
      debugPrint('POS Sales Revenue (gross, before expenses): $totalRevenue');
      debugPrint('Credit Reductions (always subtracted from revenue): $totalCreditReductions');
      debugPrint('POS Sales Revenue (net, after expenses and credit reductions): $netRevenue');
      debugPrint('Wholesale Orders Revenue: $wholesaleRevenue');
      debugPrint('Wholesale Orders Profit: $wholesaleProfit');
      debugPrint('Wholesale Transactions: $wholesaleTransactions');
      debugPrint('Recovery Balance (from sales only): $totalRecoveryBalance');
      debugPrint('Credit Used (tracked separately, NOT in revenue): $totalCreditUsed');
      debugPrint('Total Revenue (POS + Wholesale + Recovery): $totalRevenueWithRecovery');
      if (_selectedDays == 0) {
        debugPrint('NOTE: "Today" selected - showing OVERALL total revenue (all time)');
      }
      debugPrint('Note: Recovery balance is NOT double-counted (excluded from sale revenue)');
      debugPrint('Note: Credit is tracked separately and NOT included in revenue');
      debugPrint('Borrow payments are EXCLUDED from revenue');
      debugPrint('==========================');
      
      // Calculate today's revenue for breakdown (when "Today" is selected)
      // Credit reductions should be subtracted from revenue breakdown
      final todayRevenueForBreakdown = (_selectedDays == 0) 
          ? todayRevenue - totalCreditReductions  // Today's revenue minus all credit reductions
          : netRevenue;   // Filtered revenue for date range (already includes credit reductions)
      
      // Calculate today's recovery balance for breakdown (when "Today" is selected)
      final todayRecoveryForBreakdown = (_selectedDays == 0)
          ? todayRecoveryBalance  // Today's recovery only
          : totalRecoveryBalance; // Filtered recovery for date range
      
      // Calculate today's credit used for breakdown (when "Today" is selected)
      final todayCreditForBreakdown = (_selectedDays == 0)
          ? todayCreditUsed  // Today's credit only
          : totalCreditUsed; // Filtered credit for date range
      
      return {
        'totalRevenue': totalRevenueWithRecovery, // Total revenue including POS + Wholesale + recovery balance
        'salesRevenue': netRevenue, // POS sales revenue only (after returns and expenses)
        'todayRevenue': todayRevenueForBreakdown, // Today's revenue for breakdown (when "Today" is selected)
        'todayRecoveryBalance': todayRecoveryForBreakdown, // Today's recovery for breakdown (when "Today" is selected)
        'todayCreditUsed': todayCreditForBreakdown, // Today's credit used for breakdown (when "Today" is selected)
        'wholesaleRevenue': wholesaleRevenue, // Wholesale orders revenue
        'wholesaleProfit': wholesaleProfit, // Wholesale orders profit
        'wholesaleTransactions': wholesaleTransactions, // Number of wholesale orders
        'totalProfit': netProfit, // Total profit (POS + Wholesale) after expenses
        'borrowProfit': borrowProfit, // Profit from unpaid portions (will transfer to real profit when paid)
        'totalProfitWithBorrow': totalProfitWithBorrow, // Total profit (real + borrow profit)
        'totalExpenses': totalExpenses,
        'totalReturned': totalReturned, // Total amount returned (for display)
        'totalRecoveryBalance': totalRecoveryBalance, // Recovery balance from actual sales only
        'totalCreditUsed': totalCreditUsed, // Total credit balance used from sellers
        'totalBorrowed': totalBorrowed,
        'totalLent': totalLent,
        'netBorrow': netBorrow,
        'totalUnpaidSales': totalUnpaidSales,
        'todayBorrowPayments': todayBorrowPayments, // Sum of borrow payments made today
        'totalTransactions': totalTransactions + wholesaleTransactions, // POS + Wholesale transactions
        'posTransactions': totalTransactions, // POS transactions only
        'averageTransaction': (totalTransactions + wholesaleTransactions) > 0 
            ? totalRevenueWithRecovery / (totalTransactions + wholesaleTransactions) 
            : 0,
      };
    } catch (e) {
      debugPrint('Error in _calculateCombinedStats: $e');
      // Return default values on error
      return {
        'totalRevenue': 0.0,
        'salesRevenue': 0.0,
        'wholesaleRevenue': 0.0,
        'wholesaleProfit': 0.0,
        'wholesaleTransactions': 0,
        'totalProfit': 0.0,
        'borrowProfit': 0.0,
        'totalProfitWithBorrow': 0.0,
        'totalExpenses': 0.0,
        'totalReturned': 0.0,
        'totalRecoveryBalance': 0.0,
        'totalCreditUsed': 0.0,
        'totalBorrowed': 0.0,
        'totalLent': 0.0,
        'netBorrow': 0.0,
        'totalUnpaidSales': 0.0,
        'todayBorrowPayments': 0.0,
        'totalTransactions': 0,
        'averageTransaction': 0.0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: Column(
          children: [
            // Time period selector and profit toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Profit visibility toggle
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _showProfit ? Icons.visibility : Icons.visibility_off,
                          color: _showProfit ? Colors.teal : Colors.grey,
                        ),
                        onPressed: _toggleProfitVisibility,
                        tooltip: _showProfit ? 'Hide Profit' : 'Show Profit',
                      ),
                      Text(
                        _showProfit ? 'Hide Profit' : 'Show Profit',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      DropdownButton<int?>(
                        value: _selectedDays,
                        icon: const Icon(Icons.arrow_drop_down),
                        underline: Container(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Today')),
                          DropdownMenuItem(value: 7, child: Text('Last 7 Days')),
                          DropdownMenuItem(value: 30, child: Text('Last 30 Days')),
                          DropdownMenuItem(value: 90, child: Text('Last 90 Days')),
                          DropdownMenuItem(value: null, child: Text('Custom Range')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            if (value == null) {
                              _showCustomDatePicker();
                            } else {
                              _selectedDays = value;
                              _customStartDate = null;
                              _customEndDate = null;
                            }
                          });
                        },
                      ),
                      if (_customStartDate != null && _customEndDate != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: TextButton.icon(
                            onPressed: _showCustomDatePicker,
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(
                              '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd').format(_customEndDate!)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats Cards (filtered by date) - Real-time updates
                      StreamBuilder<List<Sale>>(
                        stream: salesService.getSalesStream(),
                        builder: (context, salesSnapshot) {
                          return StreamBuilder<List<Expense>>(
                            stream: expenseService.getExpensesStream(),
                            builder: (context, expensesSnapshot) {
                              return StreamBuilder<List<Borrow>>(
                                stream: borrowService.getBorrowsStream(),
                                builder: (context, borrowsSnapshot) {
                                  return StreamBuilder<double>(
                                    stream: sellerService.getTotalUnpaidSalesStream(),
                                    builder: (context, unpaidSnapshot) {
                                      // Get date range for filtering
                                      final startDate = _getStartDate();
                                      final endDate = _getEndDate();
                                      
                                      return StreamBuilder<double>(
                                        stream: sellerService.getBorrowProfitStreamByDateRange(startDate, endDate),
                                        builder: (context, borrowProfitSnapshot) {
                                          return StreamBuilder<double>(
                                            stream: sellerService.getRealProfitFromPaidStreamByDateRange(startDate, endDate),
                                            builder: (context, realProfitSnapshot) {
                                              return StreamBuilder<List<SellerOrder>>(
                                                stream: sellerOrderService.getAllOrders(),
                                                builder: (context, sellerOrdersSnapshot) {
                                                  return StreamBuilder<double>(
                                                    stream: sellerService.getTotalCreditBalanceStream(),
                                                    builder: (context, creditBalanceSnapshot) {
                                                      return StreamBuilder<double>(
                                                        stream: sellerService.getTotalCreditReductionsStream(),
                                                        builder: (context, creditReductionsSnapshot) {
                                                          // Check if all streams have data
                                                          if (!salesSnapshot.hasData || 
                                                              !expensesSnapshot.hasData || 
                                                              !borrowsSnapshot.hasData ||
                                                              !unpaidSnapshot.hasData ||
                                                              !borrowProfitSnapshot.hasData ||
                                                              !realProfitSnapshot.hasData ||
                                                              !sellerOrdersSnapshot.hasData ||
                                                              !creditBalanceSnapshot.hasData ||
                                                              !creditReductionsSnapshot.hasData) {
                                                            return const Center(
                                                              child: Padding(
                                                                padding: EdgeInsets.all(40.0),
                                                                child: CircularProgressIndicator(),
                                                              ),
                                                            );
                                                          }

                                                          // Get total credit reductions
                                                          // For "Today" view, use all credit reductions (all time)
                                                          // For date ranges, we need to filter by date
                                                          double totalCreditReductions = creditReductionsSnapshot.data ?? 0.0;
                                                          
                                                          // If not "Today", we need to filter credit reductions by date range
                                                          // Since the stream gives all reductions, we'll need to fetch filtered ones
                                                          if (_selectedDays != 0) {
                                                            // For date ranges, we'll use all reductions for now
                                                            // In a production app, you'd want a filtered stream method
                                                            // But since credit reductions should always reduce revenue regardless of date,
                                                            // using all reductions is actually correct
                                                            totalCreditReductions = creditReductionsSnapshot.data ?? 0.0;
                                                          }
                                                          
                                                          debugPrint('Dashboard - Total Credit Reductions: $totalCreditReductions');

                                                          // Calculate stats from stream data
                                                          final stats = _calculateCombinedStats(
                                                            salesSnapshot.data!,
                                                            expensesSnapshot.data!,
                                                            borrowsSnapshot.data!,
                                                            sellerOrdersSnapshot.data!,
                                                            unpaidSnapshot.data!,
                                                            borrowProfitSnapshot.data!,
                                                            realProfitSnapshot.data!,
                                                            totalCreditReductions,
                                                          );
                                                          final formatter = NumberFormat.currency(symbol: 'Rs. ');

                                                          return Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            _selectedDays == 0 ? 'Today\'s Overview' : 'Overview',
                                                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 22,
                                                                ),
                                                          ),
                                                          if (_selectedDays == 0)
                                                            Padding(
                                                              padding: const EdgeInsets.only(top: 4),
                                                              child: Text(
                                                                DateFormat('EEEE, MMMM dd, yyyy').format(DateTime.now()),
                                                                style: TextStyle(
                                                                  color: Colors.grey[600],
                                                                  fontSize: 14,
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      if (_selectedDays != 0)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 6,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blue.shade50,
                                                            borderRadius: BorderRadius.circular(20),
                                                          ),
                                                          child: Text(
                                                            _getDateRangeLabel(),
                                                            style: TextStyle(
                                                              color: Colors.blue.shade700,
                                                              fontWeight: FontWeight.w600,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: _RevenueCard(
                                                          revenue: stats['totalRevenue'], // Total revenue including recovery (credit is tracked separately, not included)
                                                          recoveryBalance: stats['totalRecoveryBalance'],
                                                          creditUsed: stats['totalCreditUsed'],
                                                          todayRevenue: stats['todayRevenueForBreakdown'] ?? stats['todayRevenue'] ?? stats['salesRevenue'], // Today's revenue for breakdown (already includes credit reductions)
                                                          todayRecoveryBalance: stats['todayRecoveryBalance'] ?? stats['totalRecoveryBalance'], // Today's recovery for breakdown
                                                          todayCreditUsed: stats['todayCreditUsed'] ?? stats['totalCreditUsed'], // Today's credit used for breakdown
                                                          totalCreditReductions: totalCreditReductions, // Pass credit reductions for display
                                                          isTodaySelected: _selectedDays == 0, // Whether "Today" is selected
                                                          formatter: formatter,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: _ModernStatCard(
                                                          title: 'Total Credit Balance',
                                                          value: formatter.format(creditBalanceSnapshot.data ?? 0.0),
                                                          icon: Icons.account_balance_wallet,
                                                          color: Colors.purple,
                                                          gradient: LinearGradient(
                                                            colors: [Colors.purple.shade400, Colors.purple.shade600],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: _ProfitCard(
                                                          realProfit: stats['totalProfit'],
                                                          borrowProfit: stats['borrowProfit'],
                                                          totalProfit: stats['totalProfitWithBorrow'],
                                                          showProfit: _showProfit,
                                                          formatter: formatter,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: _ModernStatCard(
                                                          title: 'Expenses',
                                                          value: formatter.format(stats['totalExpenses']),
                                                          icon: Icons.receipt_long,
                                                          color: Colors.red,
                                                          gradient: LinearGradient(
                                                            colors: [Colors.red.shade400, Colors.red.shade600],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: _ModernStatCard(
                                                          title: 'Returns',
                                                          value: formatter.format(stats['totalReturned']),
                                                          icon: Icons.assignment_return,
                                                          color: Colors.orange,
                                                          gradient: LinearGradient(
                                                            colors: [Colors.orange.shade400, Colors.orange.shade600],
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: _ModernStatCard(
                                                          title: 'Profit Margin',
                                                          value: _showProfit
                                                              ? (stats['totalRevenue'] > 0 
                                                                  ? '${((stats['totalProfit'] / stats['totalRevenue']) * 100).toStringAsFixed(1)}%'
                                                                  : '0%')
                                                              : '●●%',
                                                          icon: Icons.percent,
                                                          color: Colors.indigo,
                                                          gradient: LinearGradient(
                                                            colors: [Colors.indigo.shade400, Colors.indigo.shade600],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: StreamBuilder<List<Product>>(
                                                          stream: productService.getProductsStream(),
                                                          builder: (context, productSnapshot) {
                                                            final totalProducts = productSnapshot.data?.length ?? 0;
                                                            return _ModernStatCard(
                                                              title: 'Total Products',
                                                              value: totalProducts.toString(),
                                                              icon: Icons.inventory_2,
                                                              color: Colors.purple,
                                                              gradient: LinearGradient(
                                                                colors: [Colors.purple.shade400, Colors.purple.shade600],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      Expanded(
                                                        child: _BorrowCard(
                                                          totalBorrowed: stats['totalBorrowed'],
                                                          totalLent: stats['totalLent'],
                                                          netBorrow: stats['netBorrow'],
                                                          totalUnpaidSales: stats['totalUnpaidSales'],
                                                          todayBorrowPayments: stats['todayBorrowPayments'],
                                                          formatter: formatter,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              );
                                                    },
                                                  );
                                                },
                                              );
                                                        },
                                                      );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Sales Chart
                      Text(
                        'Sales Trend',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _SalesChart(
                        startDate: _getStartDate(),
                        endDate: _getEndDate(),
                        selectedDays: _selectedDays,
                        showProfit: _showProfit,
                      ),

                      const SizedBox(height: 32),

                      // Low Stock Alert
                      Text(
                        'Low Stock Alert',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<List<Product>>(
                stream: productService.getLowStockProducts(10),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final products = snapshot.data!;

                  if (products.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green.shade600,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'All products have sufficient stock',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red.shade600,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${product.category}${product.formattedSize.isNotEmpty ? ' • ${product.formattedSize}' : ''}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Stock: ${product.stock}',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

                      const SizedBox(height: 32),

                      // Recent Sales
                      Text(
                        'Recent Sales',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 16),
                      StreamBuilder<List<Sale>>(
                stream: salesService.getSalesStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final sales = snapshot.data!.take(5).toList();

                  if (sales.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              'No sales yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sales.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sale = sales[index];
                        final formatter = NumberFormat.currency(symbol: 'Rs. ');
                        final dateFormatter = DateFormat('hh:mm a');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.shopping_cart,
                              color: Colors.green.shade600,
                              size: 24,
                            ),
                          ),
                          title: Row(
                            children: [
                              if (sale.returnedAmount > 0) ...[
                                Text(
                                  formatter.format(sale.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                formatter.format(sale.netTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (sale.isBorrowPayment) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.account_balance_wallet, size: 12, color: Colors.amber.shade900),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Borrow',
                                        style: TextStyle(
                                          color: Colors.amber.shade900,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${sale.items.length} items • ${dateFormatter.format(sale.createdAt)}',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              if (sale.customerName != null && sale.customerName!.isNotEmpty)
                                Text(
                                  sale.customerName!,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              if (sale.returnedAmount > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Returned: ${formatter.format(sale.returnedAmount)}',
                                  style: TextStyle(
                                    color: Colors.orange.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (_showProfit && sale.netProfit > 0 && !sale.isBorrowPayment) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Profit: ${formatter.format(sale.netProfit)}',
                                  style: TextStyle(
                                    color: Colors.teal.shade600,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (sale.isBorrowPayment) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Borrow Payment',
                                  style: TextStyle(
                                    color: Colors.amber.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              sale.paymentMethod,
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfitCard extends StatelessWidget {
  final double realProfit;
  final double borrowProfit;
  final double totalProfit;
  final bool showProfit;
  final NumberFormat formatter;

  const _ProfitCard({
    required this.realProfit,
    required this.borrowProfit,
    required this.totalProfit,
    required this.showProfit,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade400, Colors.teal.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.trending_up, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          const Text(
            'Profit',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            showProfit 
                ? formatter.format(totalProfit)
                : '●●●●●',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Breakdown: Real Profit and Borrow Profit
          Row(
            children: [
              // Left side - Real Profit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Real Profit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      showProfit
                          ? formatter.format(realProfit)
                          : '●●●●●',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Right side - Borrow Profit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Borrow Profit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      showProfit
                          ? formatter.format(borrowProfit)
                          : '●●●●●',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BorrowCard extends StatelessWidget {
  final double totalBorrowed;
  final double totalLent;
  final double netBorrow;
  final double totalUnpaidSales;
  final double todayBorrowPayments;
  final NumberFormat formatter;

  const _BorrowCard({
    required this.totalBorrowed,
    required this.totalLent,
    required this.netBorrow,
    required this.totalUnpaidSales,
    required this.todayBorrowPayments,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade400, Colors.amber.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          const Text(
            'Borrow',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(totalBorrowed),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Unpaid Sales
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Unpaid Sales',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Text(
                  formatter.format(totalUnpaidSales),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Today's Borrow Payments (only show if > 0)
          if (todayBorrowPayments > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Today\'s Payments',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    formatter.format(todayBorrowPayments),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lent',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    formatter.format(totalLent),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                width: 1,
                height: 30,
                color: Colors.white.withOpacity(0.3),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Net',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    formatter.format(netBorrow),
                    style: TextStyle(
                      color: netBorrow >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final double revenue; // Total revenue including recovery balance (credit is tracked separately, not included)
  final double recoveryBalance;
  final double creditUsed; // Credit balance used from sellers
  final double todayRevenue; // Today's revenue for breakdown (when "Today" is selected, already includes credit reductions)
  final double todayRecoveryBalance; // Today's recovery balance for breakdown (when "Today" is selected)
  final double todayCreditUsed; // Today's credit used for breakdown (when "Today" is selected)
  final double totalCreditReductions; // Total credit reductions (for display)
  final bool isTodaySelected; // Whether "Today" is selected
  final NumberFormat formatter;

  const _RevenueCard({
    required this.revenue, // This is totalRevenueWithRecovery
    required this.recoveryBalance,
    required this.creditUsed,
    required this.todayRevenue,
    required this.todayRecoveryBalance,
    required this.todayCreditUsed,
    required this.totalCreditReductions,
    required this.isTodaySelected,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Total
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.trending_up, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Revenue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatter.format(revenue), // revenue already includes recoveryBalance
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Breakdown - Three columns: Revenue (Cash), Credit, Recovery
          Row(
            children: [
              // Left side - Revenue (Cash)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Revenue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatter.format(isTodaySelected 
                          ? todayRevenue - todayRecoveryBalance  // Today's revenue (already includes credit reductions) - recovery
                          : revenue - recoveryBalance), // Cash revenue only (excluding recovery, credit not included in revenue)
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Middle - Credit Used
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Credit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatter.format(isTodaySelected 
                          ? todayCreditUsed  // Today's credit only
                          : creditUsed), // Filtered credit for date range
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Right side - Recovery Balance
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Recovery',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatter.format(isTodaySelected 
                          ? todayRecoveryBalance  // Today's recovery only
                          : recoveryBalance), // Filtered recovery for date range
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModernStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Gradient gradient;

  const _ModernStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesChart extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final int? selectedDays;
  final bool showProfit;

  const _SalesChart({
    required this.startDate,
    required this.endDate,
    required this.selectedDays,
    required this.showProfit,
  });

  @override
  Widget build(BuildContext context) {
    final salesService = SalesService();
    final expenseService = ExpenseService();
    final sellerService = SellerService();
    final now = DateTime.now();
    final days = selectedDays ?? endDate.difference(startDate).inDays;

    return StreamBuilder<List<Sale>>(
      stream: salesService.getSalesByDateRange(startDate, endDate),
      builder: (context, salesSnapshot) {
        return StreamBuilder<List<Expense>>(
          stream: expenseService.getExpensesByDateRange(startDate, endDate),
          builder: (context, expensesSnapshot) {
            return FutureBuilder<double>(
              future: sellerService.getTotalCreditReductionsByDateRange(startDate, endDate),
              builder: (context, creditReductionsSnapshot) {
                if (!salesSnapshot.hasData || !expensesSnapshot.hasData || !creditReductionsSnapshot.hasData) {
                  return Container(
                    height: 320,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                final sales = salesSnapshot.data!;
                final expenses = expensesSnapshot.data!;
                final totalCreditReductions = creditReductionsSnapshot.data ?? 0.0;
            // Group sales by date
            Map<String, double> dailySales = {};
            Map<String, double> dailyProfit = {};
            Map<String, double> dailyExpenses = {};
            
            // Generate date keys for the range
            final dateRange = <DateTime>[];
            final currentDate = DateTime(startDate.year, startDate.month, startDate.day);
            final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
            
            var tempDate = currentDate;
            while (tempDate.isBefore(endDateOnly) || tempDate.isAtSameMomentAs(endDateOnly)) {
              dateRange.add(tempDate);
              tempDate = tempDate.add(const Duration(days: 1));
            }
            
            for (final date in dateRange) {
              final dateKey = DateFormat('MM/dd').format(date);
              dailySales[dateKey] = 0.0;
              dailyProfit[dateKey] = 0.0;
              dailyExpenses[dateKey] = 0.0;
            }

            // Add sales data
            // IMPORTANT: Match the main dashboard calculation
            // Revenue = amountPaid - recoveryBalance - change - cashPortionOfReturn (credit is NOT included in revenue)
            for (var sale in sales) {
              // Skip borrow payments - they should NOT affect revenue
              if (sale.isBorrowPayment) {
                continue;
              }
              
              final dateKey = DateFormat('MM/dd').format(sale.createdAt);
              if (dailySales.containsKey(dateKey)) {
                // Use the same revenue calculation as main dashboard
                // Revenue = cash payment only, minus cash portion of returns (credit portion doesn't affect revenue)
                double cashPaid = sale.amountPaid - sale.recoveryBalance;
                double totalPaid = cashPaid + sale.creditUsed;
                double cashPortionOfReturn = 0.0;
                if (sale.returnedAmount > 0 && totalPaid > 0) {
                  cashPortionOfReturn = sale.returnedAmount * (cashPaid / totalPaid);
                }
                final saleRevenue = sale.amountPaid - sale.recoveryBalance - sale.change - cashPortionOfReturn;
                dailySales[dateKey] = (dailySales[dateKey] ?? 0) + saleRevenue;
                dailyProfit[dateKey] = (dailyProfit[dateKey] ?? 0) + sale.netProfit; // Use net profit
              }
            }

            // Add expenses data
            for (var expense in expenses) {
              final dateKey = DateFormat('MM/dd').format(expense.createdAt);
              if (dailyExpenses.containsKey(dateKey)) {
                dailyExpenses[dateKey] = (dailyExpenses[dateKey] ?? 0) + expense.amount;
                // Subtract expenses from profit
                if (dailyProfit.containsKey(dateKey)) {
                  dailyProfit[dateKey] = (dailyProfit[dateKey] ?? 0) - expense.amount;
                }
              }
            }

            final maxValue = dailySales.values.isEmpty
                ? 1000.0
                : dailySales.values.reduce((a, b) => a > b ? a : b);

            return Container(
              height: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Sales Revenue',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Revenue: ${NumberFormat.currency(symbol: 'Rs. ').format((dailySales.values.fold(0.0, (a, b) => a + b)) - totalCreditReductions)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (showProfit)
                            Text(
                              'Profit: ${NumberFormat.currency(symbol: 'Rs. ').format(dailyProfit.values.fold(0.0, (a, b) => a + b))}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            'Expenses: ${NumberFormat.currency(symbol: 'Rs. ').format(dailyExpenses.values.fold(0.0, (a, b) => a + b))}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          selectedDays == 0
                              ? 'Today'
                              : selectedDays != null
                                  ? 'Last $selectedDays days'
                                  : '${startDate.day}/${startDate.month} - ${endDate.day}/${endDate.month}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: dailySales.isEmpty || maxValue == 0
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.insert_chart_outlined,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No sales data available',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _CustomBarChart(
                            data: dailySales,
                            maxValue: maxValue,
                          ),
                  ),
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }
}

class _CustomBarChart extends StatelessWidget {
  final Map<String, double> data;
  final double maxValue;

  const _CustomBarChart({
    required this.data,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    final displayInterval = entries.length > 20 ? 3 : entries.length > 10 ? 2 : 1;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: entries.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final date = item.key;
              final value = item.value;
              final heightPercent = maxValue > 0 ? value / maxValue : 0.0;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Value tooltip on hover
                      if (value > 0)
                        Tooltip(
                          message: NumberFormat.currency(symbol: 'Rs. ').format(value),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              value > 999
                                  ? NumberFormat.compact().format(value)
                                  : '',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      // Bar
                      Flexible(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          height: heightPercent * 180,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.green.shade600,
                                Colors.green.shade400,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Date label
                      if (index % displayInterval == 0)
                        Text(
                          date.split('/')[1],
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        )
                      else
                        const SizedBox(height: 14),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // X-axis line
        Container(
          height: 2,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}
