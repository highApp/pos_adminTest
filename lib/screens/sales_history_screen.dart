import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/seller_order.dart';
import '../models/seller.dart';
import '../services/sales_service.dart';
import '../services/product_service.dart';
import '../services/seller_order_service.dart';
import '../services/seller_service.dart';
import '../services/printer_service.dart';
import '../services/receipt_pdf_service.dart';
import '../utils/pdf_download_stub.dart' if (dart.library.html) '../utils/pdf_download_web.dart' as pdf_download;

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  static const String _profitVisibilityPassword = '5202';

  final SalesService _salesService = SalesService();
  final SellerOrderService _sellerOrderService = SellerOrderService();
  final SellerService _sellerService = SellerService();
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _filterByDate = false;
  String _transactionTypeFilter = 'all'; // 'all', 'pos', 'wholesale'
  /// Profit lines are hidden until password [ _profitVisibilityPassword ] is entered.
  bool _showProfitInSalesHistory = false;

  @override
  void initState() {
    super.initState();
    // Default: show today's sales
    final now = DateTime.now();
    _filterByDate = true;
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by seller name, description, customer, or sale ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
          // Filter Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Transaction Type Filter
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'pos', label: Text('POS')),
                    ButtonSegment(value: 'wholesale', label: Text('Wholesale')),
                  ],
                  selected: {_transactionTypeFilter},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _transactionTypeFilter = newSelection.first;
                    });
                  },
                  style: ButtonStyle(
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                // Date Filter
                IconButton(
                  icon: Icon(_filterByDate ? Icons.filter_alt : Icons.filter_alt_outlined),
                  onPressed: _showDateFilter,
                ),
                IconButton(
                  tooltip: _showProfitInSalesHistory
                      ? 'Hide profit'
                      : 'Show profit (password)',
                  icon: Icon(
                    _showProfitInSalesHistory ? Icons.lock_open : Icons.lock_outline,
                    color: _showProfitInSalesHistory ? Colors.teal : Colors.grey,
                  ),
                  onPressed: () {
                    if (_showProfitInSalesHistory) {
                      _confirmHideProfit();
                    } else {
                      _showProfitUnlockDialog();
                    }
                  },
                ),
              ],
            ),
          ),
          // Sales List
          Expanded(
            child: Column(
              children: [
                if (_filterByDate && _startDate != null && _endDate != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.blue.shade50,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Showing: ${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _filterByDate = false;
                              _startDate = null;
                              _endDate = null;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<Sale>>(
                    stream: _filterByDate && _startDate != null && _endDate != null
                        ? _salesService.getSalesByDateRange(_startDate!, _endDate!)
                        : _salesService.getSalesStream(),
                    builder: (context, salesSnapshot) {
                      return StreamBuilder<List<SellerOrder>>(
                        stream: _sellerOrderService.getAllOrders(),
                        builder: (context, ordersSnapshot) {
                          if (salesSnapshot.connectionState == ConnectionState.waiting ||
                              ordersSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (salesSnapshot.hasError) {
                            return Center(child: Text('Error: ${salesSnapshot.error}'));
                          }

                          if (ordersSnapshot.hasError) {
                            return Center(child: Text('Error: ${ordersSnapshot.error}'));
                          }

                          var sales = salesSnapshot.data ?? [];
                          var orders = ordersSnapshot.data ?? [];

                          // Filter orders by date if needed
                          if (_filterByDate && _startDate != null && _endDate != null) {
                            orders = orders.where((order) {
                              final orderDate = order.completedAt ?? order.createdAt;
                              return orderDate.isAfter(_startDate!.subtract(const Duration(seconds: 1))) &&
                                     orderDate.isBefore(_endDate!.add(const Duration(days: 1)));
                            }).toList();
                          }

                          // Filter by transaction type
                          if (_transactionTypeFilter == 'pos') {
                            orders = [];
                          } else if (_transactionTypeFilter == 'wholesale') {
                            sales = [];
                          }

                          // Apply search filter (seller name will be filtered in the widget builder)
                          final searchQuery = _searchController.text.toLowerCase().trim();
                          if (searchQuery.isNotEmpty) {
                            // First filter by fields we can check directly
                            sales = sales.where((sale) {
                              // Search in description
                              if (sale.description != null && 
                                  sale.description!.toLowerCase().contains(searchQuery)) {
                                return true;
                              }
                              // Search in customer name
                              if (sale.customerName != null && 
                                  sale.customerName!.toLowerCase().contains(searchQuery)) {
                                return true;
                              }
                              // Search in sale ID
                              if (sale.id.toLowerCase().contains(searchQuery)) {
                                return true;
                              }
                              // Search in item names
                              if (sale.items.any((item) => 
                                  item.productName.toLowerCase().contains(searchQuery))) {
                                return true;
                              }
                              // If sale has sellerId, include it (seller name will be checked in builder)
                              // If no sellerId and no other match, exclude it
                              return sale.sellerId != null;
                            }).toList();
                          }

                          // Create combined list
                          final combinedTransactions = <Map<String, dynamic>>[];
                          
                          // Add sales
                          for (var sale in sales) {
                            combinedTransactions.add({
                              'type': 'pos',
                              'date': sale.createdAt,
                              'data': sale,
                            });
                          }

                          // Add completed wholesale orders
                          for (var order in orders.where((o) => o.status == OrderStatus.completed)) {
                            combinedTransactions.add({
                              'type': 'wholesale',
                              'date': order.completedAt ?? order.createdAt,
                              'data': order,
                            });
                          }

                          // Sort by date (newest first)
                          combinedTransactions.sort((a, b) =>
                              (b['date'] as DateTime).compareTo(a['date'] as DateTime));

                          // Group POS sales by seller + same day (expandable when 2+)
                          final dateFmt = DateFormat('yyyy-MM-dd');
                          final posBySellerDay = <String, List<Map<String, dynamic>>>{};
                          final singleRows = <Map<String, dynamic>>[];

                          for (var t in combinedTransactions) {
                            if (t['type'] == 'wholesale') {
                              singleRows.add(t);
                              continue;
                            }
                            final sale = t['data'] as Sale;
                            final d = t['date'] as DateTime;
                            final dayKey = dateFmt.format(d);
                            final sellerId = sale.sellerId ?? '';
                            final key = '${sellerId}_$dayKey';
                            posBySellerDay.putIfAbsent(key, () => []).add(t);
                          }

                          final listRows = <Map<String, dynamic>>[];
                          for (var entry in posBySellerDay.entries) {
                            final list = entry.value;
                            if (list.length == 1) {
                              singleRows.add(list.first);
                            } else {
                              listRows.add({
                                'type': 'group',
                                'date': (list.first['date'] as DateTime),
                                'sellerId': (list.first['data'] as Sale).sellerId,
                                'sales': list.map((e) => e['data'] as Sale).toList(),
                              });
                            }
                          }
                          for (var t in singleRows) {
                            listRows.add({
                              'type': 'single',
                              'date': t['date'] as DateTime,
                              'transaction': t,
                            });
                          }
                          listRows.sort((a, b) =>
                              (b['date'] as DateTime).compareTo(a['date'] as DateTime));

                          if (listRows.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No transactions yet',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Sales and orders will appear here',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: listRows.length,
                            itemBuilder: (context, index) {
                              final row = listRows[index];
                              if (row['type'] == 'group') {
                                final sellerId = row['sellerId'] as String?;
                                final sales = row['sales'] as List<Sale>;
                                final date = row['date'] as DateTime;
                                return _SellerDayGroupTile(
                                  sellerId: sellerId,
                                  date: date,
                                  sales: sales,
                                  searchQuery: searchQuery,
                                  sellerService: _sellerService,
                                  showProfit: _showProfitInSalesHistory,
                                  onReturn: (sale) => _showReturnDialog(context, sale),
                                );
                              }
                              final t = row['transaction'] as Map<String, dynamic>;
                              if (t['type'] == 'pos') {
                                final sale = t['data'] as Sale;
                                if (searchQuery.isNotEmpty && sale.sellerId != null) {
                                  return FutureBuilder<Seller?>(
                                    future: _sellerService.getSellerById(sale.sellerId!),
                                    builder: (context, sellerSnapshot) {
                                      if (sellerSnapshot.hasData &&
                                          sellerSnapshot.data != null) {
                                        final seller = sellerSnapshot.data!;
                                        if (!seller.name
                                            .toLowerCase()
                                            .contains(searchQuery)) {
                                          return const SizedBox.shrink();
                                        }
                                      }
                                      return _SaleCard(
                                        sale: sale,
                                        showProfit: _showProfitInSalesHistory,
                                        onReturn: () =>
                                            _showReturnDialog(context, sale),
                                      );
                                    },
                                  );
                                }
                                return _SaleCard(
                                  sale: sale,
                                  showProfit: _showProfitInSalesHistory,
                                  onReturn: () => _showReturnDialog(context, sale),
                                );
                              } else {
                                final order = t['data'] as SellerOrder;
                                return _WholesaleOrderCard(
                                  order: order,
                                  showProfit: _showProfitInSalesHistory,
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfitUnlockDialog() {
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ProfitUnlockDialog(
        expectedPassword: _profitVisibilityPassword,
        onWrongPassword: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect password'),
              backgroundColor: Colors.red,
            ),
          );
        },
      ),
    ).then((unlocked) {
      if (!mounted || unlocked != true) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _showProfitInSalesHistory = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profit details are visible'),
            backgroundColor: Colors.green,
          ),
        );
      });
    });
  }

  void _confirmHideProfit() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hide profit'),
        content: const Text(
          'Hide profit amounts on this screen until unlocked again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _showProfitInSalesHistory = false);
              });
            },
            child: const Text('Hide'),
          ),
        ],
      ),
    );
  }

  void _showReturnDialog(BuildContext context, Sale sale) {
    // Check if there are any items that can be returned
    final returnableItems = sale.items.where((item) => item.remainingQuantity > 0).toList();
    
    if (returnableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All items have already been returned')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SaleReturnScreen(sale: sale),
      ),
    );
  }

  void _showDateFilter() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Date'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Today'),
              onTap: () {
                final now = DateTime.now();
                setState(() {
                  _filterByDate = true;
                  _startDate = DateTime(now.year, now.month, now.day);
                  _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Last 7 Days'),
              onTap: () {
                final now = DateTime.now();
                setState(() {
                  _filterByDate = true;
                  _startDate = now.subtract(const Duration(days: 7));
                  _endDate = now;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Last 30 Days'),
              onTap: () {
                final now = DateTime.now();
                setState(() {
                  _filterByDate = true;
                  _startDate = now.subtract(const Duration(days: 30));
                  _endDate = now;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Custom Range'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  ),
                );
                if (picked != null) {
                  setState(() {
                    _filterByDate = true;
                    _startDate = picked.start;
                    _endDate = picked.end;
                  });
                }
              },
            ),
            const Divider(),
            ListTile(
              title: const Text('Show All'),
              onTap: () {
                setState(() {
                  _filterByDate = false;
                  _startDate = null;
                  _endDate = null;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns [TextEditingController] so it is disposed only after the route removes the [TextField]
/// (disposing from the parent [showDialog] `.then` caused "used after disposed" on Chrome).
class _ProfitUnlockDialog extends StatefulWidget {
  const _ProfitUnlockDialog({
    required this.expectedPassword,
    required this.onWrongPassword,
  });

  final String expectedPassword;
  final VoidCallback onWrongPassword;

  @override
  State<_ProfitUnlockDialog> createState() => _ProfitUnlockDialogState();
}

class _ProfitUnlockDialogState extends State<_ProfitUnlockDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final password = _controller.text.trim();
    if (password == widget.expectedPassword) {
      Navigator.of(context).pop(true);
    } else {
      widget.onWrongPassword();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Show profit'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        keyboardType: TextInputType.text,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => unawaited(_submit()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => unawaited(_submit()),
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

/// Expandable tile for multiple POS sales by the same seller on the same day.
class _SellerDayGroupTile extends StatelessWidget {
  final String? sellerId;
  final DateTime date;
  final List<Sale> sales;
  final String searchQuery;
  final SellerService sellerService;
  final bool showProfit;
  final void Function(Sale sale) onReturn;

  const _SellerDayGroupTile({
    required this.sellerId,
    required this.date,
    required this.sales,
    required this.searchQuery,
    required this.sellerService,
    required this.showProfit,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateStr = DateFormat('MMM dd, yyyy').format(date);
    final totalAmount =
        sales.fold<double>(0.0, (sum, s) => sum + s.total);
    final future = sellerId != null
        ? Future.wait([
            sellerService.getSellerById(sellerId!),
            sellerService.getTotalDueAmountForSeller(sellerId!),
            sellerService.getCreditBalance(sellerId!),
          ])
        : Future.value(<dynamic>[null, 0.0, 0.0]);
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final seller = snapshot.data != null && snapshot.data!.isNotEmpty
            ? snapshot.data![0] as Seller?
            : null;
        final due = snapshot.data != null && snapshot.data!.length > 1
            ? (snapshot.data![1] as num).toDouble()
            : 0.0;
        final credit = snapshot.data != null && snapshot.data!.length > 2
            ? (snapshot.data![2] as num).toDouble()
            : 0.0;
        final sellerName = seller?.name ?? 'No seller';
        if (searchQuery.isNotEmpty &&
            !sellerName.toLowerCase().contains(searchQuery)) {
          return const SizedBox.shrink();
        }
        final dueCreditParts = <String>[];
        if (due > 0.01) dueCreditParts.add('Due: ${formatter.format(due)}');
        if (credit > 0.01) dueCreditParts.add('Credit: ${formatter.format(credit)}');
        final dueCreditStr = dueCreditParts.isEmpty
            ? ''
            : ' • ${dueCreditParts.join(' • ')}';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: Colors.green.shade50,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade200,
                child: Icon(Icons.person, color: Colors.green.shade800),
              ),
              title: Text(
                sellerName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                '$dateStr • ${sales.length} sale(s) • ${formatter.format(totalAmount)} total$dueCreditStr',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                ),
              ),
              children: sales
                  .map(
                    (sale) => Padding(
                      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                      child: _SaleCard(
                        sale: sale,
                        showProfit: showProfit,
                        onReturn: () => onReturn(sale),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _SaleCard extends StatelessWidget {
  final Sale sale;
  final bool showProfit;
  final VoidCallback onReturn;

  const _SaleCard({
    required this.sale,
    required this.showProfit,
    required this.onReturn,
  });

  Future<Seller?> _getSeller(String? sellerId) async {
    if (sellerId == null) return null;
    final sellerService = SellerService();
    return await sellerService.getSellerById(sellerId);
  }

  Future<void> _handleViewPdf(BuildContext context) async {
    Seller? seller;
    if (sale.sellerId != null) {
      seller = await _getSeller(sale.sellerId);
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await ReceiptPdfService.generateSaleReceiptPdf(
        sale,
        seller: seller,
        existingDueTotal: sale.existingDueTotalAtSale,
        contextForUrduRendering: context,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sale Receipt'),
          content: SizedBox(
            width: 600,
            height: 700,
            child: PdfPreview(
              build: (format) async => bytes,
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Same thermal print path as POS payment success → Print (WiFi / BT / USB).
  Future<void> _handlePrintReceipt(BuildContext context) async {
    final printerService = PrinterService();
    try {
      final connectionType = await printerService.getConnectionType();
      var needsConfiguration = false;
      if (connectionType == PrinterConnectionType.wifi) {
        final printerIp = await printerService.getPrinterIp();
        needsConfiguration = printerIp == null || printerIp.isEmpty;
      } else if (connectionType == PrinterConnectionType.bluetooth) {
        final btDeviceId = await printerService.getBluetoothDeviceId();
        needsConfiguration = btDeviceId == null;
      } else if (connectionType == PrinterConnectionType.usb) {
        final usbDeviceId = await printerService.getUsbDeviceId();
        needsConfiguration = usbDeviceId == null;
      }

      if (needsConfiguration) {
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Printer not configured'),
              content: const Text(
                'Set up your thermal printer from the POS screen (complete a test sale and use Print, or printer options there), then try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      Seller? seller;
      if (sale.sellerId != null) {
        seller = await _getSeller(sale.sellerId);
      }
      if (!context.mounted) return;

      final lang = await printerService.getReceiptLanguage();
      final success = await printerService.printReceipt(
        sale,
        sale.existingDueTotalAtSale,
        seller,
        languageCode: lang,
      );

      if (!context.mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt printed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        var errorMessage =
            'Failed to print receipt. Please check printer connection.';
        if (kIsWeb &&
            connectionType == PrinterConnectionType.bluetooth) {
          errorMessage =
              'Bluetooth printing from the browser often fails. Try WiFi printer or print from the mobile app.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Sales history print receipt: $e');
      debugPrint('$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDownloadPdf(BuildContext context) async {
    Seller? seller;
    if (sale.sellerId != null) {
      seller = await _getSeller(sale.sellerId);
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await ReceiptPdfService.generateSaleReceiptPdf(
        sale,
        seller: seller,
        existingDueTotal: sale.existingDueTotalAtSale,
        contextForUrduRendering: context,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final filename = 'sale-${sale.id.substring(0, 8).toUpperCase()}.pdf';
      pdf_download.downloadPdf(bytes, filename);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF downloaded: $filename'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy hh:mm a');

    final hasReturns = sale.returnedAmount > 0;
    final canReturn = sale.items.any((item) => item.remainingQuantity > 0);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: hasReturns ? Colors.orange.shade100 : Colors.green.shade100,
          child: Icon(
            hasReturns ? Icons.assignment_return : Icons.receipt, 
            color: hasReturns ? Colors.orange.shade700 : Colors.green.shade700,
          ),
        ),
        title: Row(
          children: [
            Text(
              formatter.format(sale.total),
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 18,
                decoration: hasReturns ? TextDecoration.lineThrough : null,
              ),
            ),
            if (hasReturns) ...[
              const SizedBox(width: 8),
              Text(
                formatter.format(sale.netTotal),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateFormatter.format(sale.createdAt)),
            Row(
              children: [
                if (sale.isBorrowPayment)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          'Borrow',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (sale.saleType == 'wholesale')
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Wholesale',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text('${sale.items.length} item(s) • ${sale.paymentMethod}'),
              ],
            ),
            if (sale.sellerId != null)
              FutureBuilder<Seller?>(
                future: _getSeller(sale.sellerId),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final seller = snapshot.data!;
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.blue[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Seller: ${seller.name}',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            if (sale.sellerId != null)
              FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  SellerService().getTotalDueAmountForSeller(sale.sellerId!),
                  SellerService().getCreditBalance(sale.sellerId!),
                ]),
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.length < 2) return const SizedBox.shrink();
                  final due = (snap.data![0] as num).toDouble();
                  final credit = (snap.data![1] as num).toDouble();
                  if (due < 0.01 && credit < 0.01) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (due > 0.01)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pending_actions, size: 14, color: Colors.orange.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Due: ${formatter.format(due)}',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        if (credit > 0.01)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_wallet, size: 14, color: Colors.teal.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Credit: ${formatter.format(credit)}',
                                style: TextStyle(
                                  color: Colors.teal.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            if (sale.customerName != null && sale.customerName!.isNotEmpty)
              Text(
                sale.customerName!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            if (sale.description != null && sale.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.description, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sale.description!,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasReturns)
              Text(
                'Returned: ${formatter.format(sale.returnedAmount)}',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            if (showProfit && sale.netProfit > 0 && !sale.isBorrowPayment)
              Text(
                'Profit: ${formatter.format(sale.netProfit)}',
                style: TextStyle(
                  color: Colors.teal.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            if (sale.isBorrowPayment)
              Text(
                'Borrow Payment - No Profit',
                style: TextStyle(
                  color: Colors.amber.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Receipt options',
              onSelected: (value) async {
                if (value == 'print_receipt') {
                  await _handlePrintReceipt(context);
                }
                if (value == 'view_pdf') await _handleViewPdf(context);
                if (value == 'download_pdf') await _handleDownloadPdf(context);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'print_receipt',
                  child: ListTile(
                    leading: Icon(Icons.print),
                    title: Text('Print receipt'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'view_pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('View PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'download_pdf',
                  child: ListTile(
                    leading: Icon(Icons.download),
                    title: Text('Download PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            if (canReturn)
              IconButton(
                icon: const Icon(Icons.assignment_return, color: Colors.orange),
                onPressed: onReturn,
                tooltip: 'Return Items',
              ),
          ],
        ),
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Items:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...sale.items.map((item) {
                  final showLineEconomics =
                      showProfit && !sale.isBorrowPayment;
                  final lineNetProfit = showLineEconomics
                      ? item.netLineProfit(sale)
                      : null;
                  final pp = item.purchasePrice;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.productName} x${item.quantity}'),
                              if (item.returnedQuantity > 0)
                                Text(
                                  'Returned: ${item.returnedQuantity}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (showLineEconomics) ...[
                              if (pp != null)
                                Text(
                                  'Cost/u: ${formatter.format(pp)}',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 11,
                                  ),
                                ),
                              if (lineNetProfit != null) ...[
                                Text(
                                  item.remainingQuantity <= 0
                                      ? 'Line profit: —'
                                      : 'Line profit: ${formatter.format(lineNetProfit)}',
                                  style: TextStyle(
                                    color: Colors.teal.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                            ],
                            Text(
                              formatter.format(item.subtotal),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:'),
                    Text(
                      formatter.format(sale.total),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        decoration: hasReturns ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
                if (hasReturns) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Returned:'),
                      Text(
                        '- ${formatter.format(sale.returnedAmount)}',
                        style: TextStyle(
                          color: Colors.orange.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Total:'),
                      Text(
                        formatter.format(sale.netTotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
                if (showProfit && sale.netProfit > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Profit:'),
                      Text(
                        formatter.format(sale.netProfit),
                        style: TextStyle(
                          color: Colors.teal.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Paid:'),
                    Text(formatter.format(sale.amountPaid)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Change:'),
                    Text(
                      formatter.format(sale.change),
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
                if (sale.description != null && sale.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.description, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Description:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sale.description!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[800],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (sale.sellerId != null)
                  FutureBuilder<Seller?>(
                    future: _getSeller(sale.sellerId),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        final seller = snapshot.data!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 16, color: Colors.blue[600]),
                              const SizedBox(width: 8),
                              Text(
                                'Seller: ${seller.name}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const SizedBox(height: 8),
                Text(
                  'ID: ${sale.id}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Sale Return Screen
class SaleReturnScreen extends StatefulWidget {
  final Sale sale;

  const SaleReturnScreen({super.key, required this.sale});

  @override
  State<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends State<SaleReturnScreen> {
  final SalesService _salesService = SalesService();
  final ProductService _productService = ProductService();
  final Map<String, double> _returnQuantities = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Initialize return quantities to 0
    for (var item in widget.sale.items) {
      if (item.remainingQuantity > 0) {
        _returnQuantities[item.productId] = 0.0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final returnableItems = widget.sale.items
        .where((item) => item.remainingQuantity > 0)
        .toList();

    double totalReturnAmount = 0;
    for (var item in returnableItems) {
      final returnQty = _returnQuantities[item.productId] ?? 0.0;
      totalReturnAmount += item.price * returnQty;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Return Items'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Return info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sale ID: ${widget.sale.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Original Total: ${formatter.format(widget.sale.total)}'),
                if (widget.sale.returnedAmount > 0)
                  Text(
                    'Previously Returned: ${formatter.format(widget.sale.returnedAmount)}',
                    style: TextStyle(color: Colors.orange.shade700),
                  ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: returnableItems.length,
              itemBuilder: (context, index) {
                final item = returnableItems[index];
                final returnQty = _returnQuantities[item.productId] ?? 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Price: ${formatter.format(item.price)} each'),
                        Text('Available to return: ${item.remainingQuantity}'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Return Quantity:'),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: returnQty > 0
                                  ? () {
                                      setState(() {
                                        // Support fractional quantities for weight-based items
                                        final decrement = returnQty % 1 == 0 ? 1.0 : 0.1;
                                        _returnQuantities[item.productId] = (returnQty - decrement).clamp(0.0, item.remainingQuantity);
                                      });
                                    }
                                  : null,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                returnQty.toStringAsFixed(returnQty % 1 == 0 ? 0 : 1),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: returnQty < item.remainingQuantity
                                  ? () {
                                      setState(() {
                                        // Support fractional quantities for weight-based items
                                        final increment = returnQty % 1 == 0 ? 1.0 : 0.1;
                                        _returnQuantities[item.productId] = (returnQty + increment).clamp(0.0, item.remainingQuantity);
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        if (returnQty > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Refund: ${formatter.format(item.price * returnQty)}',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Refund:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatter.format(totalReturnAmount),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: totalReturnAmount > 0 && !_isProcessing
                        ? _processReturn
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Process Return',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processReturn() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Fill missing cost from product so net profit can use line-accurate math after save
      final resolvedPurchaseByProductId = <String, double>{};
      for (var item in widget.sale.items) {
        if (item.productId.isEmpty) continue;
        if (item.purchasePrice != null) {
          resolvedPurchaseByProductId[item.productId] = item.purchasePrice!;
          continue;
        }
        try {
          final p = await _productService.getProductById(item.productId);
          if (p != null) {
            resolvedPurchaseByProductId[item.productId] = p.purchasePrice;
          }
        } catch (_) {}
      }

      // Calculate total return amount
      double totalReturnAmount = 0;
      final updatedItems = <SaleItem>[];
      final stockUpdates = <String, double>{}; // Track stock updates

      // First, prepare all updates
      for (var item in widget.sale.items) {
        final returnQty = _returnQuantities[item.productId] ?? 0.0;
        final newReturnedQty = item.returnedQuantity + returnQty;

        totalReturnAmount += item.price * returnQty;

        final resolvedPp = item.purchasePrice ??
            resolvedPurchaseByProductId[item.productId];

        // Create updated sale item
        updatedItems.add(SaleItem(
          productId: item.productId,
          productName: item.productName,
          price: item.price,
          quantity: item.quantity,
          subtotal: item.subtotal,
          returnedQuantity: newReturnedQty,
          purchasePrice: resolvedPp,
        ));

        // Track stock updates (accumulate if same product appears multiple times)
        if (returnQty > 0) {
          stockUpdates[item.productId] = (stockUpdates[item.productId] ?? 0.0) + returnQty;
        }
      }

      // Update stock for each returned item
      for (var entry in stockUpdates.entries) {
        try {
          print('Updating stock for product ${entry.key}: adding ${entry.value} units');
          await _productService.updateStock(entry.key, entry.value);
          print('Stock updated successfully for product ${entry.key}');
        } catch (e) {
          print('Error updating stock for product ${entry.key}: $e');
          throw Exception('Failed to restore stock for product ${entry.key}');
        }
      }

      // Store previous returned amount before update
      final previousReturnedAmount = widget.sale.returnedAmount;
      
      // Create updated sale - IMPORTANT: Preserve all original sale fields including creditUsed and recoveryBalance
      final updatedSale = Sale(
        id: widget.sale.id,
        items: updatedItems,
        total: widget.sale.total,
        profit: widget.sale.profit,
        amountPaid: widget.sale.amountPaid,
        change: widget.sale.change,
        createdAt: widget.sale.createdAt,
        customerName: widget.sale.customerName,
        paymentMethod: widget.sale.paymentMethod,
        returnedAmount: widget.sale.returnedAmount + totalReturnAmount,
        isPartialReturn: true,
        sellerId: widget.sale.sellerId, // Preserve sellerId for return processing
        recoveryBalance: widget.sale.recoveryBalance, // Preserve recovery balance
        creditUsed: widget.sale.creditUsed, // Preserve original credit used (critical for proportional credit restoration)
        isBorrowPayment: widget.sale.isBorrowPayment, // Preserve borrow payment flag
        saleType: widget.sale.saleType, // Preserve sale type
        description: widget.sale.description, // Preserve description
        existingDueTotalAtSale: widget.sale.existingDueTotalAtSale,
      );

      // Update sale in database and update seller history if needed
      await _salesService.processSaleReturn(updatedSale, previousReturnedAmount: previousReturnedAmount);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Return processed: ${NumberFormat.currency(symbol: 'Rs. ').format(totalReturnAmount)} refunded\n'
              'Stock restored for ${stockUpdates.length} product(s)',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error in _processReturn: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing return: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}

// Wholesale Order Card Widget
class _WholesaleOrderCard extends StatelessWidget {
  final SellerOrder order;
  final bool showProfit;

  const _WholesaleOrderCard({
    required this.order,
    required this.showProfit,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy hh:mm a');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.business, color: Colors.blue.shade700),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'WHOLESALE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.sellerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.sellerPhone,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatter.format(order.total),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.green,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.sellerLocation,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                dateFormatter.format(order.completedAt ?? order.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          // Order Items
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              return ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.shopping_bag, size: 20, color: Colors.blue.shade700),
                ),
                title: Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Qty: ${item.quantity.toInt()} × ${formatter.format(item.wholesalePrice)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatter.format(item.subtotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (showProfit)
                      Text(
                        'Profit: ${formatter.format(item.profit)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          // Summary
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Items:',
                      style: TextStyle(fontSize: 14),
                    ),
                    Text(
                      '${order.items.length} items',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatter.format(order.total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                if (showProfit) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Profit:',
                        style: TextStyle(fontSize: 14, color: Colors.blue),
                      ),
                      Text(
                        formatter.format(order.profit),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

