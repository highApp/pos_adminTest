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
import '../models/seller.dart';
import '../models/seller_reminder.dart';
import '../services/seller_reminder_service.dart';
import '../services/reset_data_service.dart';
import '../services/balance_service.dart';
import '../services/buyer_payment_service.dart';
import '../models/balance_entry.dart';
import 'seller_history_screen.dart';
import '../widgets/dashboard_sync_strip.dart';

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
  final sellerReminderService = SellerReminderService();
  final resetDataService = ResetDataService();
  final balanceService = BalanceService();
  final buyerPaymentService = BuyerPaymentService();
  late final Future<DateTime?> _resetDateFuture;
  late Future<_AllTimeBorrowTotals> _allTimeBorrowTotalsFuture;
  int? _selectedDays = 0; // -1 = All, 0 = Today, 7/30/90 = Last N Days, null = custom date range
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _showProfit = false; // Hide profit by default

  /// Borrow-book leg only. All-time **seller** due comes from the live `seller_history` stream
  /// (`UnpaidSalesDashboardTotals.allTimeOutstandingFromHistory`) so it drops immediately after payments.
  Future<_AllTimeBorrowTotals> _loadAllTimeBorrowTotals() async {
    final book = await borrowService.getTotalOutstandingBorrowedAllTime();
    return _AllTimeBorrowTotals(
      borrowBookBorrowedOutstanding: book,
    );
  }

  @override
  void initState() {
    super.initState();
    _resetDateFuture = resetDataService.getFinancialResetDate();
    _allTimeBorrowTotalsFuture = _loadAllTimeBorrowTotals();
  }

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

  void _showRecoveryDetailsDialog(
    BuildContext context,
    List<Map<String, dynamic>> recoveryDetails,
    SellerService sellerService,
    NumberFormat formatter,
  ) {
    if (recoveryDetails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recovery entries in this period')),
      );
      return;
    }
    // Sort by date descending (newest first)
    final sorted = List<Map<String, dynamic>>.from(recoveryDetails)
      ..sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Text('Recovery details'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<Map<String?, String>>(
            future: () async {
              final names = <String?, String>{};
              for (var e in sorted) {
                final id = e['sellerId'] as String?;
                if (id == null || id.isEmpty || names.containsKey(id)) continue;
                final seller = await sellerService.getSellerById(id);
                names[id] = seller?.name ?? 'Unknown';
              }
              return names;
            }(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sellerNames = snapshot.data!;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount collected from sellers (payment against dues)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...sorted.map((e) {
                      final sellerId = e['sellerId'] as String?;
                      final amount = (e['amount'] as num).toDouble();
                      final createdAt = e['createdAt'] as DateTime;
                      final name = (sellerId != null && sellerId.isNotEmpty)
                          ? (sellerNames[sellerId] ?? 'Unknown')
                          : '—';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('MMM d, h:mm a').format(createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatter.format(amount),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showCreditDetailsDialog(
    BuildContext context,
    List<Map<String, dynamic>> creditDetails,
    SellerService sellerService,
    NumberFormat formatter,
  ) {
    if (creditDetails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No credit applied in this period')),
      );
      return;
    }
    final sorted = List<Map<String, dynamic>>.from(creditDetails)
      ..sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: Colors.purple.shade700),
            const SizedBox(width: 10),
            const Text('Credit details'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<Map<String?, String>>(
            future: () async {
              final names = <String?, String>{};
              for (var e in sorted) {
                final id = e['sellerId'] as String?;
                if (id == null || id.isEmpty || names.containsKey(id)) continue;
                final seller = await sellerService.getSellerById(id);
                names[id] = seller?.name ?? 'Unknown';
              }
              return names;
            }(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sellerNames = snapshot.data!;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seller credit balance applied at checkout (not cash received)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...sorted.map((e) {
                      final sellerId = e['sellerId'] as String?;
                      final amount = (e['amount'] as num).toDouble();
                      final createdAt = e['createdAt'] as DateTime;
                      final name = (sellerId != null && sellerId.isNotEmpty)
                          ? (sellerNames[sellerId] ?? 'Unknown')
                          : '—';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('MMM d, h:mm a').format(createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatter.format(amount),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.purple.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showBuyerPaidDetailsDialog(
    BuildContext context,
    DateTime startDate,
    DateTime endDate,
    NumberFormat formatter,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.people_alt_outlined, color: Colors.blue.shade700),
            const SizedBox(width: 10),
            const Text('Buyer paid details'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: buyerPaymentService.getBuyerPaidSummaryByDateRange(
              startDate,
              endDate,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Could not load buyer payment details.'),
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No buyer payments in selected date range.'),
                );
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buyer-wise payments for ${_getDateRangeLabel()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...rows.map((row) {
                      final buyerName =
                          (row['buyerName'] as String?)?.trim().isNotEmpty == true
                              ? row['buyerName'] as String
                              : 'Unknown buyer';
                      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                buyerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatter.format(amount),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTodayStillDueSellersDialog(
    BuildContext context,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final fmt = NumberFormat.currency(symbol: 'Rs. ');
    final rangeTitle = _getDateRangeLabel();
    // Single future so rebuilds don’t restart the request; avoids blank / stuck UI.
    final loadFuture = sellerService.getOutstandingDueBySellerForDateRange(
      rangeStart,
      rangeEnd,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final screenH = MediaQuery.sizeOf(dialogContext).height;
        return AlertDialog(
          icon: Icon(Icons.groups_outlined, color: Colors.amber.shade800),
          iconColor: Colors.amber.shade800,
          title: Text(
            'Sellers — $rangeTitle',
            style: theme.textTheme.titleLarge,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<TodaySellerDueSummary>>(
              future: loadFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading sellers…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return SelectableText(
                    'Could not load list.\n${snapshot.error}',
                    style: TextStyle(color: Colors.red.shade800, fontSize: 14),
                  );
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No remaining due on seller bills in this period ($rangeTitle).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade800,
                      ),
                    ),
                  );
                }
                return SizedBox(
                  height: (screenH * 0.45).clamp(120.0, 420.0),
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade300),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final initial = r.sellerName.isNotEmpty
                          ? r.sellerName[0].toUpperCase()
                          : '?';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 2,
                          horizontal: 0,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.shade100,
                          child: Text(
                            initial,
                            style: TextStyle(color: Colors.amber.shade900),
                          ),
                        ),
                        title: Text(
                          r.sellerName,
                          style: theme.textTheme.bodyLarge,
                        ),
                        subtitle: Text(
                          r.sellerId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Text(
                          fmt.format(r.remainingDue),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(dialogContext);
                          final s = await sellerService.getSellerById(r.sellerId);
                          if (!context.mounted) return;
                          if (s == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Seller not found')),
                            );
                            return;
                          }
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SellerHistoryScreen(seller: s),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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
    } else if (_selectedDays == -1) {
      // All time (balance entries and data from beginning)
      return DateTime(2000);
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
    } else if (_selectedDays == -1) {
      // All time
      return DateTime(now.year, now.month, now.day, 23, 59, 59);
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
    } else if (_selectedDays == -1) {
      return 'All';
    } else if (_selectedDays == 0) {
      return 'Today';
    } else {
      return 'Last $_selectedDays Days';
    }
  }

  // Calculate combined stats from stream data (for real-time updates)
  // If [resetDate] is set, only data on or after that date is counted (for Revenue/Credit/Recovery).
  Map<String, dynamic> _calculateCombinedStats(
    List<Sale> sales,
    List<Expense> expenses,
    List<Borrow> borrows,
    List<SellerOrder> sellerOrders,
    List<BalanceEntry> balanceEntries,
    double periodOutstandingFromSellerHistory,
    double borrowProfit,
    double realProfitFromPaid,
    double periodCreditReductions, // Credit reductions for the selected date range (Today, Last N Days, or Custom)
    [DateTime? resetDate,
  ]) {
    try {
      final startDate = _getStartDate();
      final endDate = _getEndDate();
      // When user has done "Reset Revenue & Credit", only count data on or after reset date
      final effectiveStartDate = (resetDate != null && resetDate.isAfter(startDate))
          ? resetDate
          : startDate;

      // Filter sales by date range (respecting reset date)
      final filteredSales = sales.where((sale) {
        return sale.createdAt.isAfter(effectiveStartDate.subtract(const Duration(seconds: 1))) &&
               sale.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();

      // Filter expenses by date range (respecting reset date)
      final filteredExpenses = expenses.where((expense) {
        return expense.createdAt.isAfter(effectiveStartDate.subtract(const Duration(seconds: 1))) &&
               expense.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();

      // Filter borrows by date range (respecting reset date)
      final filteredBorrows = borrows.where((borrow) {
        return borrow.createdAt.isAfter(effectiveStartDate.subtract(const Duration(seconds: 1))) &&
               borrow.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();

      // Filter completed seller orders by date range (respecting reset date)
      final filteredSellerOrders = sellerOrders.where((order) {
        return order.status == OrderStatus.completed &&
               order.completedAt != null &&
               order.completedAt!.isAfter(effectiveStartDate.subtract(const Duration(seconds: 1))) &&
               order.completedAt!.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList();

      // Filter balance entries by date range (manual revenue from Add Balance)
      final filteredBalanceEntries = balanceEntries.where((entry) {
        final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
        return !entryDate.isBefore(effectiveStartDate) && !entryDate.isAfter(DateTime(endDate.year, endDate.month, endDate.day));
      }).toList();
      final totalBalanceEntries = filteredBalanceEntries.fold<double>(0.0, (sum, e) => sum + e.amount);

      // Always use filtered orders for revenue (respects date filter: Today, Last N Days, or Custom Range)
      final ordersForRevenue = filteredSellerOrders;
      
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
      double totalCreditAdded = 0; // Credit added from manual overpayments (when payment > due amount)
      double todayCreditAdded = 0; // Today's credit added only (for breakdown when "Today" is selected)
      /// In dashboard date range: `isBorrowPayment` sales (repayments).
      double periodPosBorrowRepayments = 0;
      /// In dashboard date range: cash applied to seller `seller_history` dues — manual “due payment”
      /// sales and POS checkout when part of payment goes to existing dues ([Sale.recoveryBalance]).
      double periodSellerDueRepayments = 0;
      /// In dashboard date range: normal sales with change < 0 (POS “Borrow” shortfall).
      double periodPosBorrowShortfall = 0;
      int totalTransactions = 0;
      
      // Track sales for profit calculation
      final salesMap = <String, Sale>{};
      // Recovery details for "tap to see breakdown" (seller, amount, date per sale)
      final recoveryDetails = <Map<String, dynamic>>[];
      // Credit used details (seller credit applied at checkout), same period filter as dashboard
      final creditDetails = <Map<String, dynamic>>[];

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      // Always use filtered sales for revenue (respects date filter: Today, Last N Days, or Custom Range)
      final salesForRevenue = filteredSales;
      
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
          //
          // IMPORTANT: Manual payment with overpayment (e.g. pay 10000 when due is 5000):
          //   amountPaid = 10000, recoveryBalance = 5000 (to dues), remainder 5000 = credit added
          //   The credit portion (5000) should go to Credit column, NOT Revenue
          final isManualPaymentSale = sale.total == 0 && (sale.customerName?.startsWith('Manual Payment') ?? false);
          final creditAddedFromOverpayment = isManualPaymentSale && sale.amountPaid > sale.recoveryBalance
              ? sale.amountPaid - sale.recoveryBalance
              : 0.0;

          double cashPaid = sale.amountPaid - sale.recoveryBalance;
          double totalPaid = cashPaid + sale.creditUsed;
          double cashPortionOfReturn = 0.0;
          if (sale.returnedAmount > 0 && totalPaid > 0) {
            // Calculate what portion of the return was originally paid with cash
            cashPortionOfReturn = sale.returnedAmount * (cashPaid / totalPaid);
          }
          // For manual payment with overpayment: exclude credit portion from revenue (it goes to Credit column)
          final saleRevenue = isManualPaymentSale
              ? 0.0  // Manual payments: recovery goes to Recovery, excess goes to Credit - no revenue
              : sale.amountPaid - sale.recoveryBalance - sale.change - cashPortionOfReturn;
          totalRevenue += saleRevenue;
          
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
          
          // Track credit added from manual overpayments (when payment > due, excess becomes credit)
          totalCreditAdded += creditAddedFromOverpayment;

          // If "Today" is selected, also calculate today's revenue separately for breakdown
          if (_selectedDays == 0 && 
              sale.createdAt.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
              sale.createdAt.isBefore(todayEnd.add(const Duration(seconds: 1)))) {
            todayRevenue += saleRevenue;
            todayRecoveryBalance += sale.recoveryBalance;
            todayCreditUsed += netCreditUsed; // Use net credit used (after returns)
            todayCreditAdded += creditAddedFromOverpayment;
          }
          
          // Store sale for profit calculation from seller_history
          salesMap[sale.id] = sale;
          
          totalTransactions++;
          // Only include recovery balance from actual sales (not borrow payments)
          // Recovery balance from sales represents money received from paying off due payments
          // This excludes borrow payments which have isBorrowPayment = true
          totalRecoveryBalance += sale.recoveryBalance;
          if (sale.recoveryBalance > 0) {
            recoveryDetails.add({
              'saleId': sale.id,
              'sellerId': sale.sellerId,
              'amount': sale.recoveryBalance,
              'createdAt': sale.createdAt,
            });
            // Repayment toward seller dues (manual payment or POS cash allocated to old bills).
            periodSellerDueRepayments += sale.recoveryBalance;
          }
          // Track net credit balance used (after accounting for returns)
          totalCreditUsed += netCreditUsed;
          if (netCreditUsed > 0) {
            creditDetails.add({
              'saleId': sale.id,
              'sellerId': sale.sellerId,
              'amount': netCreditUsed,
              'createdAt': sale.createdAt,
            });
          }

          // POS shortfall in selected period (sales list is already filtered by dashboard dates).
          if (sale.change < 0) {
            periodPosBorrowShortfall += -sale.change;
          }
        } else {
          // Skip borrow payments completely - they should not affect revenue
          // Borrow payments are tracked separately in the borrow section only
          debugPrint('Skipping borrow payment from revenue: ${sale.id}, amount: ${sale.total}');
          
          // Borrow repayments in selected period (same filtered sales stream).
          if (sale.isBorrowPayment) {
            periodPosBorrowRepayments += sale.amountPaid;
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
      
      // periodCreditReductions is passed as parameter (filtered by selected date range)
      
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
      // Seller unpaid + borrow book, both scoped to the dashboard date filter only.
      final totalBorrowHeadline =
          periodOutstandingFromSellerHistory + totalBorrowed;

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
      
      // Always subtract credit reductions and expenses from revenue for the selected date range
      final netRevenue = grossRevenue - totalExpenses - periodCreditReductions;
      
      // Total revenue including recovery balance, credit added from overpayments, wholesale orders, AND manual balance entries (Add Balance)
      // Revenue = sales (cash) + recovery + credit added (from manual overpayments) + wholesale + balance entries (manual revenue)
      // NOTE: Credit used is NOT included (it's money already received when credit was given)
      // NOTE: Credit added from manual overpayments IS included (new money received, saved as seller's credit)
      // NOTE: This excludes borrow payments completely - they are NOT included in revenue
      // Borrow payments are tracked separately in the borrow section only
      final totalRevenueWithRecovery = netRevenue + totalRecoveryBalance + totalCreditAdded + wholesaleRevenue + totalBalanceEntries;
      
      debugPrint('=== REVENUE CALCULATION ===');
      debugPrint('Date Filter: ${_selectedDays == 0 ? "Today" : _getDateRangeLabel()}');
      debugPrint('POS Sales Revenue (gross, before expenses): $totalRevenue');
      debugPrint('Credit Reductions (filtered by date range): $periodCreditReductions');
      debugPrint('POS Sales Revenue (net, after expenses and credit reductions): $netRevenue');
      debugPrint('Wholesale Orders Revenue: $wholesaleRevenue');
      debugPrint('Wholesale Orders Profit: $wholesaleProfit');
      debugPrint('Wholesale Transactions: $wholesaleTransactions');
      debugPrint('Recovery Balance (from sales only): $totalRecoveryBalance');
      debugPrint('Credit Used (tracked separately, NOT in revenue): $totalCreditUsed');
      debugPrint('Credit Added (from manual overpayments, included in Total Revenue): $totalCreditAdded');
      debugPrint('Total Revenue (POS + Wholesale + Recovery): $totalRevenueWithRecovery');
      if (_selectedDays == 0) {
        debugPrint('NOTE: "Today" selected - showing TODAY\'s data only');
      }
      debugPrint('Note: Recovery balance is NOT double-counted (excluded from sale revenue)');
      debugPrint('Note: Credit used is tracked separately and NOT included in revenue (already counted when credit was given)');
      debugPrint('Borrow payments are EXCLUDED from revenue');
      debugPrint(
        'POS borrow (${_getDateRangeLabel()}): shortfall ${periodPosBorrowShortfall.toStringAsFixed(2)} '
        '− borrow-book ${periodPosBorrowRepayments.toStringAsFixed(2)} '
        '− seller dues ${periodSellerDueRepayments.toStringAsFixed(2)} '
        '= net ${(periodPosBorrowShortfall - periodPosBorrowRepayments - periodSellerDueRepayments).toStringAsFixed(2)}',
      );
      debugPrint('==========================');
      
      // Calculate revenue for breakdown display
      // When Today: show today's revenue - today's credit reductions
      // When date range: show filtered net revenue (already includes credit reductions)
      final todayRevenueForBreakdown = (_selectedDays == 0) 
          ? todayRevenue - periodCreditReductions  // Today's revenue = cash sales - period credit reductions
          : netRevenue;   // Filtered revenue for date range (already includes credit reductions)
      
      if (_selectedDays == 0) {
        debugPrint('Today Revenue Breakdown: $todayRevenueForBreakdown (cash sales - period credit reductions: $periodCreditReductions)');
      }
      
      // Calculate today's recovery balance for breakdown (when "Today" is selected)
      final todayRecoveryForBreakdown = (_selectedDays == 0)
          ? todayRecoveryBalance  // Today's recovery only
          : totalRecoveryBalance; // Filtered recovery for date range
      
      // Credit column = credit USED (applied in sales) - shows when seller pays using their credit balance
      // Credit Added (from manual overpayments) is included in Total Revenue but shown only when it happens
      // Credit Used shows credit applied in sales - e.g. yesterday 4000 credit, today applied 1500 → show 1500
      final totalCredit = totalCreditUsed;
      // Calculate today's credit for breakdown (when "Today" is selected)
      final todayCreditForBreakdown = (_selectedDays == 0)
          ? todayCreditUsed  // Today's credit applied in sales
          : totalCredit; // Filtered credit for date range
      
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
        'recoveryDetails': recoveryDetails, // Per-sale recovery for breakdown dialog (seller, amount, date)
        'creditDetails': creditDetails, // Per-sale credit used for breakdown dialog
        'totalCreditUsed': totalCredit, // Credit = credit applied in sales (credit used from seller's balance)
        'totalBorrowed': totalBorrowed,
        'totalBorrowHeadline': totalBorrowHeadline,
        'totalLent': totalLent,
        'netBorrow': netBorrow,
        'totalUnpaidSales': periodOutstandingFromSellerHistory,
        'periodPosBorrowRepayments': periodPosBorrowRepayments,
        'periodSellerDueRepayments': periodSellerDueRepayments,
        'periodPosBorrowShortfall': periodPosBorrowShortfall,
        'periodPosBorrowNet': periodPosBorrowShortfall -
            periodPosBorrowRepayments -
            periodSellerDueRepayments,
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
        'recoveryDetails': <Map<String, dynamic>>[],
        'creditDetails': <Map<String, dynamic>>[],
        'totalCreditUsed': 0.0,
        'totalBorrowed': 0.0,
        'totalBorrowHeadline': 0.0,
        'totalLent': 0.0,
        'netBorrow': 0.0,
        'totalUnpaidSales': 0.0,
        'periodPosBorrowRepayments': 0.0,
        'periodSellerDueRepayments': 0.0,
        'periodPosBorrowShortfall': 0.0,
        'periodPosBorrowNet': 0.0,
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
          setState(() {
            _allTimeBorrowTotalsFuture = _loadAllTimeBorrowTotals();
          });
          await _allTimeBorrowTotalsFuture;
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
                          DropdownMenuItem(value: -1, child: Text('All')),
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
                              if (value != null) {
                                _customStartDate = null;
                                _customEndDate = null;
                              }
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
                      const DashboardSyncStrip(),
                      const SizedBox(height: 8),
                      // Stats Cards (filtered by date) - Real-time updates
                      // Never block entire dashboard: use defaults so UI shows immediately, then updates live (no data deleted)
                      FutureBuilder<DateTime?>(
                        future: _resetDateFuture,
                        builder: (context, resetDateSnapshot) {
                          final resetDate = resetDateSnapshot.data;
                          final startDate = _getStartDate();
                          final endDate = _getEndDate();
                          final effectiveStartDate =
                              (resetDate != null && resetDate.isAfter(startDate))
                                  ? resetDate
                                  : startDate;
                          final effectiveEndDate = endDate;

                          // Force new StreamBuilder state when the range changes (avoids stale borrow/revenue
                          // snapshots after switching e.g. Last 7 Days -> All).
                          return StreamBuilder<List<Sale>>(
                            key: ValueKey<String>(
                              'dash_stats_${effectiveStartDate.toIso8601String()}_'
                              '${effectiveEndDate.toIso8601String()}_'
                              '${_selectedDays}_${resetDate?.toIso8601String() ?? 'no_reset'}',
                            ),
                            stream: salesService.getSalesByDateRange(
                              effectiveStartDate,
                              effectiveEndDate,
                            ),
                            builder: (context, salesSnapshot) {
                              return StreamBuilder<List<Expense>>(
                                stream: expenseService.getExpensesByDateRange(
                                  effectiveStartDate,
                                  effectiveEndDate,
                                ),
                                builder: (context, expensesSnapshot) {
                                  return StreamBuilder<List<Borrow>>(
                                    stream: borrowService.getBorrowsByDateRange(
                                      effectiveStartDate,
                                      effectiveEndDate,
                                    ),
                                    builder: (context, borrowsSnapshot) {
                                      return StreamBuilder<UnpaidSalesDashboardTotals>(
                                        stream: sellerService
                                            .getUnpaidSalesDashboardTotalsStream(
                                          effectiveStartDate,
                                          effectiveEndDate,
                                        ),
                                        builder: (context, unpaidSnapshot) {
                                          return StreamBuilder<DashboardSellerProfitTotals>(
                                            stream: sellerService
                                                .getDashboardSellerProfitTotalsStream(
                                              effectiveStartDate,
                                              effectiveEndDate,
                                            ),
                                            builder: (context, profitTotalsSnapshot) {
                                              final profitTotals =
                                                  profitTotalsSnapshot.data ??
                                                      DashboardSellerProfitTotals
                                                          .zero;
                                              final borrowProfit =
                                                  profitTotals.borrowProfit;
                                              final realProfit =
                                                  profitTotals.realProfit;

                                              return StreamBuilder<List<SellerOrder>>(
                                                stream: sellerOrderService
                                                    .getAllOrders(),
                                                builder: (context, sellerOrdersSnapshot) {
                                                  return StreamBuilder<List<BalanceEntry>>(
                                                    stream: balanceService
                                                        .getBalanceEntriesStream(),
                                                    builder: (context, balanceSnapshot) {
                                                      return StreamBuilder<double>(
                                                        stream: sellerService
                                                            .getTotalCreditBalanceStream(),
                                                        builder: (context, creditBalanceSnapshot) {
                                                          return StreamBuilder<double>(
                                                            stream: sellerService
                                                                .getTotalCreditReductionsStream(),
                                                            builder: (context, creditReductionsSnapshot) {
                                                              final sales = salesSnapshot.data ?? [];
                                                              final expenses = expensesSnapshot.data ?? [];
                                                              final borrows = borrowsSnapshot.data ?? [];
                                                              final unpaidTotals =
                                                                  unpaidSnapshot.data ??
                                                                      UnpaidSalesDashboardTotals
                                                                          .empty;
                                                              final sellerOrders =
                                                                  sellerOrdersSnapshot.data ??
                                                                      [];
                                                              final balanceEntries =
                                                                  balanceSnapshot.data ?? [];
                                                              final creditBalance =
                                                                  creditBalanceSnapshot.data ??
                                                                      0.0;
                                                              final creditReductions =
                                                                  creditReductionsSnapshot.data ??
                                                                      0.0;

                                                              return StreamBuilder<double>(
                                                                stream: buyerPaymentService
                                                                    .getTotalPaidByDateRangeStream(
                                                                  effectiveStartDate,
                                                                  effectiveEndDate,
                                                                ),
                                                                builder: (context, buyerPaidSnapshot) {
                                                                  final buyerPaidTotal =
                                                                      buyerPaidSnapshot.data ??
                                                                          0.0;
                                                                  return FutureBuilder<double>(
                                                                    future: sellerService
                                                                        .getTotalCreditReductionsByDateRange(
                                                                      effectiveStartDate,
                                                                      effectiveEndDate,
                                                                    ),
                                                                    builder: (context, periodCreditReductionsSnapshot) {
                                                                      final periodCreditReductions =
                                                                          periodCreditReductionsSnapshot.data ??
                                                                              0.0;

                                                                      // Calculate stats from stream data (respects reset date for Revenue/Credit/Recovery)
                                                                      final stats = _calculateCombinedStats(
                                                                        sales,
                                                                        expenses,
                                                                        borrows,
                                                                        sellerOrders,
                                                                        balanceEntries,
                                                                        unpaidTotals
                                                                            .periodOutstandingFromHistory,
                                                                        borrowProfit,
                                                                        realProfit,
                                                                        periodCreditReductions,
                                                                        resetDate,
                                                                      );
                                                                      final formatter =
                                                                          NumberFormat.currency(
                                                                        symbol: 'Rs. ',
                                                                      );

                                                                      return Column(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment
                                                                                .start,
                                                                        children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            _selectedDays == 0
                                                                ? 'Today\'s Overview'
                                                                : _selectedDays == -1
                                                                    ? 'Overall Overview'
                                                                    : 'Overview',
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
                                                      if (_selectedDays != 0 && _selectedDays != -1)
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
                                                          buyerPaid: buyerPaidTotal,
                                                          todayRevenue: stats['todayRevenueForBreakdown'] ?? stats['todayRevenue'] ?? stats['salesRevenue'], // Today's revenue for breakdown (already includes credit reductions)
                                                          todayRecoveryBalance: stats['todayRecoveryBalance'] ?? stats['totalRecoveryBalance'], // Today's recovery for breakdown
                                                          todayCreditUsed: stats['todayCreditUsed'] ?? stats['totalCreditUsed'], // Today's credit used for breakdown
                                                          totalCreditReductions: periodCreditReductions, // Pass credit reductions for display (filtered by date range)
                                                          isTodaySelected: _selectedDays == 0, // Whether "Today" is selected
                                                          formatter: formatter,
                                                          recoveryDetails: stats['recoveryDetails'] ?? [],
                                                          onRecoveryTap: () => _showRecoveryDetailsDialog(context, stats['recoveryDetails'] ?? [], sellerService, formatter),
                                                          creditDetails: stats['creditDetails'] ?? [],
                                                          onCreditTap: () => _showCreditDetailsDialog(context, stats['creditDetails'] ?? [], sellerService, formatter),
                                                          onBuyerPaidTap: () => _showBuyerPaidDetailsDialog(
                                                            context,
                                                            effectiveStartDate,
                                                            effectiveEndDate,
                                                            formatter,
                                                          ),
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
                                                          totalBorrowHeadline:
                                                              stats['totalBorrowHeadline'],
                                                          totalBorrowed:
                                                              stats['totalBorrowed'],
                                                          totalLent: stats['totalLent'],
                                                          netBorrow: stats['netBorrow'],
                                                          totalUnpaidSales:
                                                              stats['totalUnpaidSales'],
                                                          unpaidSalesRowLabel:
                                                              'Unpaid sales · ${_getDateRangeLabel()}',
                                                          periodPosBorrowRepayments:
                                                              stats['periodPosBorrowRepayments'],
                                                          periodSellerDueRepayments:
                                                              stats['periodSellerDueRepayments'],
                                                          periodPosBorrowShortfall:
                                                              stats['periodPosBorrowShortfall'],
                                                          periodPosBorrowNet:
                                                              stats['periodPosBorrowNet'],
                                                          periodLabel: _getDateRangeLabel(),
                                                          allTimeBorrowFuture:
                                                              _allTimeBorrowTotalsFuture,
                                                          liveAllTimeSellerDue: unpaidTotals
                                                              .allTimeOutstandingFromHistory,
                                                          formatter: formatter,
                                                          onTapUnpaidSalesRow: () =>
                                                              _showTodayStillDueSellersDialog(
                                                            context,
                                                            effectiveStartDate,
                                                            effectiveEndDate,
                                                          ),
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
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Today's Alert Sellers & Upcoming Sellers
                      _SellerReminderAlerts(
                        reminderService: sellerReminderService,
                        sellerService: sellerService,
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
                      FutureBuilder<DateTime?>(
                        future: _resetDateFuture,
                        builder: (context, chartResetSnap) {
                          final chartReset = chartResetSnap.data;
                          final chartStartRaw = _getStartDate();
                          final chartEndRaw = _getEndDate();
                          final chartEffectiveStart =
                              (chartReset != null && chartReset.isAfter(chartStartRaw))
                                  ? chartReset
                                  : chartStartRaw;
                          return _SalesChart(
                            startDate: chartEffectiveStart,
                            endDate: chartEndRaw,
                            selectedDays: _selectedDays,
                            showProfit: _showProfit,
                          );
                        },
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
                  final products = snapshot.data ?? [];

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
                stream: salesService.getRecentSalesStream(limit: 5),
                builder: (context, snapshot) {
                  final sales = snapshot.data ?? [];

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

/// Borrow-book “borrowed” outstanding (all time). Seller all-time due is supplied live from the stream.
class _AllTimeBorrowTotals {
  const _AllTimeBorrowTotals({
    required this.borrowBookBorrowedOutstanding,
  });

  final double borrowBookBorrowedOutstanding;
}

class _BorrowCard extends StatelessWidget {
  /// [totalBorrowHeadline] = period seller unpaid + period borrow-book "borrowed" (same date filter).
  final double totalBorrowHeadline;
  final double totalBorrowed;
  final double totalLent;
  final double netBorrow;
  /// Remaining seller `duePayment` on bills dated in the selected period only.
  final double totalUnpaidSales;
  final String unpaidSalesRowLabel;
  final double periodPosBorrowRepayments;
  final double periodSellerDueRepayments;
  final double periodPosBorrowShortfall;
  final double periodPosBorrowNet;
  final String periodLabel;
  final Future<_AllTimeBorrowTotals> allTimeBorrowFuture;
  /// Live sum of all `seller_history` rows with `duePayment` > 0 (same snapshot as period unpaid).
  final double liveAllTimeSellerDue;
  final NumberFormat formatter;
  final VoidCallback onTapUnpaidSalesRow;

  const _BorrowCard({
    required this.totalBorrowHeadline,
    required this.totalBorrowed,
    required this.totalLent,
    required this.netBorrow,
    required this.totalUnpaidSales,
    required this.unpaidSalesRowLabel,
    required this.periodPosBorrowRepayments,
    required this.periodSellerDueRepayments,
    required this.periodPosBorrowShortfall,
    required this.periodPosBorrowNet,
    required this.periodLabel,
    required this.allTimeBorrowFuture,
    required this.liveAllTimeSellerDue,
    required this.formatter,
    required this.onTapUnpaidSalesRow,
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
            'Total borrow',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(totalBorrowHeadline),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'For “$periodLabel”: seller bills dated in range + borrow-book rows created in range',
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Not the same as all-time owed — see below. Tap row for seller list.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 10,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<_AllTimeBorrowTotals>(
            future: allTimeBorrowFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Could not load all-time snapshot (pull to retry)',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 10,
                    ),
                  ),
                );
              }
              if (snap.connectionState != ConnectionState.done || !snap.hasData) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    color: Colors.white.withOpacity(0.9),
                  ),
                );
              }
              final t = snap.data!;
              final combinedAllTime =
                  liveAllTimeSellerDue + t.borrowBookBorrowedOutstanding;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All-time snapshot',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatter.format(combinedAllTime)} total '
                      '(sellers ${formatter.format(liveAllTimeSellerDue)} + borrow book ${formatter.format(t.borrowBookBorrowedOutstanding)})',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: 10,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      'Pull down to refresh · ignores date filter above',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 9,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTapUnpaidSalesRow,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_cart_outlined,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              unpaidSalesRowLabel,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatter.format(totalUnpaidSales),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.white.withOpacity(0.75),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Same date filter as Overview: shortfall (change < 0) vs borrow-payment sales.
          if (periodPosBorrowShortfall > 0 ||
              periodPosBorrowRepayments > 0 ||
              periodSellerDueRepayments > 0 ||
              periodPosBorrowNet != 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'POS borrow · $periodLabel',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Shortfall on sales (change)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        formatter.format(periodPosBorrowShortfall),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Borrow-book repayments',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '− ${formatter.format(periodPosBorrowRepayments)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Seller dues repaid',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '− ${formatter.format(periodSellerDueRepayments)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Divider(color: Colors.white.withOpacity(0.25), height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Net (this period)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        formatter.format(periodPosBorrowNet),
                        style: TextStyle(
                          color: periodPosBorrowNet > 0
                              ? Colors.orange.shade100
                              : Colors.green.shade100,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Net = shortfall − borrow-book repayments − seller dues repaid '
                    '(manual due payments and POS cash to old bills use recovery).',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 9,
                      height: 1.2,
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
  final double buyerPaid; // Buyer-side payments total for selected date range
  final double todayRevenue; // Today's revenue for breakdown (when "Today" is selected, cash sales only, excludes credit used)
  final double todayRecoveryBalance; // Today's recovery balance for breakdown (when "Today" is selected)
  final double todayCreditUsed; // Today's credit used for breakdown (when "Today" is selected)
  final double totalCreditReductions; // Total credit reductions (for display)
  final bool isTodaySelected; // Whether "Today" is selected
  final NumberFormat formatter;
  final List<Map<String, dynamic>> recoveryDetails; // Per-sale recovery for breakdown dialog
  final VoidCallback? onRecoveryTap; // When user taps Recovery to see details
  final List<Map<String, dynamic>> creditDetails; // Per-sale credit used for breakdown dialog
  final VoidCallback? onCreditTap; // When user taps Credit to see details
  final VoidCallback? onBuyerPaidTap; // When user taps Buyer Paid to see buyer-wise list

  const _RevenueCard({
    required this.revenue, // This is totalRevenueWithRecovery
    required this.recoveryBalance,
    required this.creditUsed,
    required this.buyerPaid,
    required this.todayRevenue,
    required this.todayRecoveryBalance,
    required this.todayCreditUsed,
    required this.totalCreditReductions,
    required this.isTodaySelected,
    required this.formatter,
    this.recoveryDetails = const [],
    this.onRecoveryTap,
    this.creditDetails = const [],
    this.onCreditTap,
    this.onBuyerPaidTap,
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
                          ? todayRevenue  // Today's revenue = cash sales only (includes manual sales, excludes credit used)
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
              // Middle - Credit Used (tappable for per-sale list)
              Expanded(
                child: InkWell(
                  onTap: (creditUsed > 0 && creditDetails.isNotEmpty && onCreditTap != null)
                      ? onCreditTap
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Credit',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (creditUsed > 0 && onCreditTap != null) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatter.format(isTodaySelected
                              ? todayCreditUsed
                              : creditUsed),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (creditUsed > 0 && onCreditTap != null)
                          Text(
                            'Tap for details',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Right side - Recovery Balance (tappable for details)
              Expanded(
                child: InkWell(
                  onTap: (recoveryBalance > 0 && recoveryDetails.isNotEmpty && onRecoveryTap != null)
                      ? onRecoveryTap
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Recovery',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (recoveryBalance > 0 && onRecoveryTap != null) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ],
                          ],
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
                        if (recoveryBalance > 0 && onRecoveryTap != null)
                          Text(
                            'Tap for details',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: (buyerPaid > 0 && onBuyerPaidTap != null)
                ? onBuyerPaidTap
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(
                    'Buyer Paid',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (buyerPaid > 0 && onBuyerPaidTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatter.format(buyerPaid),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                final sales = salesSnapshot.data ?? [];
                final expenses = expensesSnapshot.data ?? [];
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

class _SellerReminderAlerts extends StatelessWidget {
  final SellerReminderService reminderService;
  final SellerService sellerService;

  const _SellerReminderAlerts({
    required this.reminderService,
    required this.sellerService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Seller>>(
      stream: sellerService.getSellersStream(),
      builder: (context, sellersSnapshot) {
        final sellersMap = <String, Seller>{};
        if (sellersSnapshot.hasData) {
          for (final s in sellersSnapshot.data!) {
            sellersMap[s.id] = s;
          }
        }
        final getSellerName = (String id) => sellersMap[id]?.name ?? 'Unknown';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Today's Alert Sellers
            Text(
              'Today\'s Alert Sellers',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<SellerReminder>>(
              stream: reminderService.getRemindersDueTodayStream(),
              builder: (context, snapshot) {
                final reminders = snapshot.data ?? [];
                if (reminders.isEmpty) {
                  return _EmptyReminderCard(
                    icon: Icons.check_circle_outline,
                    message: 'No reminders due today',
                    color: Colors.green,
                  );
                }
                return _ReminderList(
                  reminders: reminders,
                  getSellerName: getSellerName,
                  isToday: true,
                  onTapReminder: (r) => _navigateToSellerDetail(context, r.sellerId, sellersMap),
                );
              },
            ),
            const SizedBox(height: 24),
            // Upcoming Sellers
            Text(
              'Upcoming Sellers',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<SellerReminder>>(
              stream: reminderService.getUpcomingRemindersStream(),
              builder: (context, snapshot) {
                final reminders = snapshot.data ?? [];
                if (reminders.isEmpty) {
                  return _EmptyReminderCard(
                    icon: Icons.event_available,
                    message: 'No upcoming reminders',
                    color: Colors.blue,
                  );
                }
                return _ReminderList(
                  reminders: reminders,
                  getSellerName: getSellerName,
                  isToday: false,
                  onTapReminder: (r) => _navigateToSellerDetail(context, r.sellerId, sellersMap),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToSellerDetail(BuildContext context, String sellerId, Map<String, Seller> sellersMap) {
    final seller = sellersMap[sellerId];
    if (seller == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SellerHistoryScreen(seller: seller),
      ),
    );
  }
}

class _EmptyReminderCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final MaterialColor color;

  const _EmptyReminderCard({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
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
              color: color.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color.shade600, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  final List<SellerReminder> reminders;
  final String Function(String) getSellerName;
  final bool isToday;
  final void Function(SellerReminder reminder) onTapReminder;

  const _ReminderList({
    required this.reminders,
    required this.getSellerName,
    required this.isToday,
    required this.onTapReminder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reminders.length,
      itemBuilder: (context, index) {
        final r = reminders[index];
        final sellerName = getSellerName(r.sellerId);
        return InkWell(
          onTap: () => onTapReminder(r),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToday ? Colors.amber.shade200 : Colors.blue.shade100,
              ),
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
                    color: isToday ? Colors.amber.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isToday ? Icons.notifications_active : Icons.schedule,
                    color: isToday ? Colors.amber.shade700 : Colors.blue.shade700,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sellerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.message,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.reminderDate.hour == 0 && r.reminderDate.minute == 0
                            ? DateFormat('MMM d, y').format(r.reminderDate)
                            : DateFormat('MMM d, y • h:mm a').format(r.reminderDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
