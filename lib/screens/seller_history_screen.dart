import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/whatsapp_share_stub.dart' if (dart.library.io) '../utils/whatsapp_share_native.dart' as whatsapp_share;
import '../models/seller.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/credit_history.dart';
import '../services/seller_service.dart';
import '../services/sales_service.dart';
import '../services/printer_service.dart';
import '../services/receipt_pdf_service.dart';
import '../utils/pdf_download_stub.dart' if (dart.library.html) '../utils/pdf_download_web.dart' as pdf_download;
import '../widgets/sync_status_banner.dart';

/// Cash kept by shop + wallet credit (POS); excludes change returned. Fallback: seller_history row.
double _ledgerTotalCreditForSalePdf(
  Map<String, dynamic>? saleData,
  double historyRowAmountPaid,
) {
  if (saleData == null) return historyRowAmountPaid;
  final cash = (saleData['amountPaid'] as num?)?.toDouble() ?? 0.0;
  final change = (saleData['change'] as num?)?.toDouble() ?? 0.0;
  final creditUsed = (saleData['creditUsed'] as num?)?.toDouble() ?? 0.0;
  // Sale doc: amountPaid = physical cash; change = returned; creditUsed = seller wallet
  return (cash - change + creditUsed) > 0 ? (cash - change + creditUsed) : historyRowAmountPaid;
}

/// Loads `sales/{id}` for ledger PDF (full cash, recovery, change). Chunked for Firestore limits.
Future<Map<String, Map<String, dynamic>>> _loadSalesMapForPdf(
  Set<String> saleIds,
) async {
  final map = <String, Map<String, dynamic>>{};
  final ids = saleIds.toList();
  const batch = 30;
  for (var i = 0; i < ids.length; i += batch) {
    final end = (i + batch) > ids.length ? ids.length : i + batch;
    final chunk = ids.sublist(i, end);
    if (chunk.isEmpty) break;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sales')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        map[d.id] = d.data();
      }
    } catch (_) {
      // batch failed — PDF falls back to seller_history amounts
    }
  }
  return map;
}

class SellerHistoryScreen extends StatefulWidget {
  final Seller seller;
  /// If set, open this dialog after the screen loads. 'due_payment' | 'manual_sale'
  final String? initialAction;

  const SellerHistoryScreen({super.key, required this.seller, this.initialAction});

  @override
  State<SellerHistoryScreen> createState() => _SellerHistoryScreenState();
}

class _SellerHistoryScreenState extends State<SellerHistoryScreen> with SingleTickerProviderStateMixin {
  final SellerService _sellerService = SellerService();
  final SalesService _salesService = SalesService();
  DateTime? _startDate;
  DateTime? _endDate;
  static const int _sellerHistoryPageSize = 40;
  List<Map<String, dynamic>> _paginatedSellerHistory = [];
  DocumentSnapshot<Map<String, dynamic>>? _paginatedSellerHistoryLastDoc;
  bool _paginatedSellerHistoryHasMore = true;
  bool _paginatedSellerHistoryInitialLoading = true;
  bool _paginatedSellerHistoryLoadingMore = false;
  String? _paginatedSellerHistoryError;
  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');
  final DateFormat _dateTimeFormatter = DateFormat('MMM dd, yyyy - hh:mm a');
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');
  late TabController _tabController;
  bool _initialActionHandled = false;
  /// Profit on expanded sale rows is hidden until password is entered (same as dashboard).
  bool _showSellerHistoryProfit = false;

  void _toggleSellerHistoryProfitVisibility() {
    if (_showSellerHistoryProfit) {
      setState(() => _showSellerHistoryProfit = false);
    } else {
      _showSellerHistoryProfitPasswordDialog();
    }
  }

  void _showSellerHistoryProfitPasswordDialog() {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
              'Enter password to view profit on sales',
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
              ),
              onSubmitted: (value) {
                _verifySellerHistoryProfitPassword(value, passwordController);
                Navigator.pop(dialogContext);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _verifySellerHistoryProfitPassword(
                passwordController.text,
                passwordController,
              );
              Navigator.pop(dialogContext);
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

  void _verifySellerHistoryProfitPassword(
    String password,
    TextEditingController controller,
  ) {
    const String correctPassword = '5202';
    if (password == correctPassword) {
      setState(() => _showSellerHistoryProfit = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Profit visible on sales'),
              ],
            ),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
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
    }
    controller.clear();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_initialActionHandled && mounted) {
          _initialActionHandled = true;
          if (widget.initialAction == 'due_payment') {
            _showDuePaymentHistory(context, 0);
          } else if (widget.initialAction == 'manual_sale') {
            _showAddManualSaleDialog(context);
          }
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sellerHistoryIsAllTimeMode) {
        _resetAndLoadSellerHistoryPage();
      }
    });
  }

  bool get _sellerHistoryIsAllTimeMode =>
      _startDate == null && _endDate == null;

  void _onSellerHistoryDateFilterChanged() {
    if (_sellerHistoryIsAllTimeMode) {
      _resetAndLoadSellerHistoryPage();
    }
  }

  Future<void> _resetAndLoadSellerHistoryPage() async {
    setState(() {
      _paginatedSellerHistory = [];
      _paginatedSellerHistoryLastDoc = null;
      _paginatedSellerHistoryHasMore = true;
      _paginatedSellerHistoryError = null;
      _paginatedSellerHistoryInitialLoading = true;
      _paginatedSellerHistoryLoadingMore = false;
    });
    await _fetchSellerHistoryPage(append: false);
  }

  Future<void> _fetchSellerHistoryPage({required bool append}) async {
    if (!mounted) return;
    if (append) {
      if (!_paginatedSellerHistoryHasMore || _paginatedSellerHistoryLoadingMore) {
        return;
      }
      setState(() => _paginatedSellerHistoryLoadingMore = true);
    }
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('seller_history')
          .where('sellerId', isEqualTo: widget.seller.id)
          .orderBy('saleDate', descending: true)
          .limit(_sellerHistoryPageSize);
      if (append && _paginatedSellerHistoryLastDoc != null) {
        q = q.startAfterDocument(_paginatedSellerHistoryLastDoc!);
      }
      final snap = await q.get();
      if (!mounted) return;
      final newRows = snap.docs
          .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
          .toList();
      setState(() {
        if (append) {
          _paginatedSellerHistory = [
            ..._paginatedSellerHistory,
            ...newRows,
          ];
        } else {
          _paginatedSellerHistory = newRows;
        }
        if (snap.docs.isNotEmpty) {
          _paginatedSellerHistoryLastDoc = snap.docs.last;
        }
        _paginatedSellerHistoryHasMore =
            snap.docs.length == _sellerHistoryPageSize;
        _paginatedSellerHistoryInitialLoading = false;
        _paginatedSellerHistoryLoadingMore = false;
        _paginatedSellerHistoryError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paginatedSellerHistoryError = e.toString();
        _paginatedSellerHistoryInitialLoading = false;
        _paginatedSellerHistoryLoadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.seller.name} - History'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.shopping_cart), text: 'Sales History'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Credit History'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showSellerHistoryProfit ? Icons.visibility : Icons.visibility_off,
              color: _showSellerHistoryProfit ? Colors.teal : null,
            ),
            tooltip: _showSellerHistoryProfit ? 'Hide profit' : 'Show profit',
            onPressed: _toggleSellerHistoryProfitVisibility,
          ),
          IconButton(
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'Add Manual Sale',
            onPressed: () => _showAddManualSaleDialog(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SyncStatusBanner(),
          Expanded(
            child: Column(
              children: [
                // Summary Cards
                _buildSummaryCards(),

                // Date Filter
                _buildDateFilter(),

                // History List
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildHistoryList(),
                      _buildCreditHistoryList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddManualSaleDialog(context),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Add Manual Sale'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  /// Full seller_history stream (slow for large histories). Used if lean queries fail.
  Widget _buildLegacySummaryCardsStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seller_history')
          .where('sellerId', isEqualTo: widget.seller.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return FutureBuilder<double>(
            future: _sellerService.getCreditBalance(widget.seller.id),
            builder: (context, creditSnapshot) {
              final creditBalance = creditSnapshot.data ?? 0.0;
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: Colors.orange.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.pending_actions,
                                          color: Colors.orange.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Current Outstanding',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.orange.shade900,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    _currencyFormatter.format(0.0),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Card(
                            color: Colors.green.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.shopping_cart,
                                          color: Colors.green.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Total Sale (net)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.green.shade900,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _currencyFormatter.format(0.0),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Credit Balance Card
                    Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet,
                                color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Credit Balance',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  creditSnapshot.connectionState == ConnectionState.waiting
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : SelectableText(
                                          _currencyFormatter.format(creditBalance),
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                            if (creditBalance > 0)
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.orange),
                                onPressed: () => _showReduceCreditBalanceDialog(context, creditBalance),
                                tooltip: 'Reduce Credit Balance',
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showEditCreditBalanceDialog(context, creditBalance),
                              tooltip: 'Edit Credit Balance',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _showDeleteCreditBalanceDialog(context),
                              tooltip: 'Delete Credit Balance and History',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        // Calculate overall totals from ALL records (not filtered)
        final allRecords = snapshot.data!.docs;
        final totalDue = allRecords.fold<double>(
          0.0,
          (sum, doc) {
            final data = doc.data() as Map<String, dynamic>;
            return sum + (data['duePayment'] ?? 0).toDouble();
          },
        );

        // When date range is set, compute period totals (due payments received + sales in period)
        final hasDateRange = _startDate != null && _endDate != null;
        final periodDocs = hasDateRange
            ? _filterRecordsByDateRange(allRecords, _startDate!, _endDate!)
            : <QueryDocumentSnapshot>[];
        final saleDocsInPeriod = hasDateRange
            ? periodDocs
                .where((d) =>
                    !_isPaymentRecord(d.data() as Map<String, dynamic>))
                .toList()
            : <QueryDocumentSnapshot>[];
        final periodDuePaymentsReceived = periodDocs.fold<double>(
          0.0,
          (sum, doc) {
            final data = doc.data() as Map<String, dynamic>;
            return sum +
                (_isPaymentRecord(data)
                    ? (data['saleAmount'] ?? 0).toDouble()
                    : 0);
          },
        );

        return FutureBuilder<List<double>>(
          future: Future.wait([
            _calculateTotalSaleFromActualSales(allRecords),
            _sellerService.getCreditBalance(widget.seller.id),
            hasDateRange
                ? _calculateTotalSaleFromActualSales(saleDocsInPeriod)
                : Future.value(0.0),
          ]),
          builder: (context, saleSnapshot) {
            final totalSale = saleSnapshot.data?[0] ?? 0.0;
            final creditBalance = saleSnapshot.data?[1] ?? 0.0;
            final periodSales = saleSnapshot.data?[2] ?? 0.0;

            final periodLabel = hasDateRange
                ? ' (${_dateFormatter.format(_startDate!)} - ${_dateFormatter.format(_endDate!)})'
                : '';

            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showDuePaymentHistory(context, totalDue),
                          borderRadius: BorderRadius.circular(12),
                          child: Card(
                            color: Colors.orange.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.pending_actions,
                                          color: Colors.orange.shade700),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          hasDateRange
                                              ? 'Paid in period$periodLabel'
                                              : 'Current Outstanding',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.orange.shade900,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    hasDateRange
                                        ? _currencyFormatter
                                            .format(periodDuePaymentsReceived)
                                        : _currencyFormatter.format(totalDue),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                  if (hasDateRange && totalDue > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Outstanding: ${_currencyFormatter.format(totalDue)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.shopping_cart,
                                        color: Colors.green.shade700),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        hasDateRange
                                            ? 'Sales$periodLabel'
                                            : 'Total Sale (net)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.green.shade900,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                saleSnapshot.connectionState ==
                                        ConnectionState.waiting
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : SelectableText(
                                        hasDateRange
                                            ? _currencyFormatter
                                                .format(periodSales)
                                            : _currencyFormatter
                                                .format(totalSale),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Credit Balance Card
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Credit Balance',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                saleSnapshot.connectionState == ConnectionState.waiting
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : SelectableText(
                                        _currencyFormatter.format(creditBalance),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                          if (creditBalance > 0)
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.orange),
                              onPressed: () => _showReduceCreditBalanceDialog(context, creditBalance),
                              tooltip: 'Reduce Credit Balance',
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditCreditBalanceDialog(context, creditBalance),
                            tooltip: 'Edit Credit Balance',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _showDeleteCreditBalanceDialog(context),
                            tooltip: 'Delete Credit Balance and History',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sellerHistoryOpenDueStream() {
    return FirebaseFirestore.instance
        .collection('seller_history')
        .where('sellerId', isEqualTo: widget.seller.id)
        .where('duePayment', isGreaterThan: 0)
        .orderBy('duePayment')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sellerHistorySaleDateInRangeStream() {
    final start = _startDate!;
    final end = _endDate!;
    final startStr =
        DateTime(start.year, start.month, start.day).toIso8601String();
    final endStr = DateTime(end.year, end.month, end.day, 23, 59, 59, 999)
        .toIso8601String();
    return FirebaseFirestore.instance
        .collection('seller_history')
        .where('sellerId', isEqualTo: widget.seller.id)
        .where('saleDate', isGreaterThanOrEqualTo: startStr)
        .where('saleDate', isLessThanOrEqualTo: endStr)
        .orderBy('saleDate')
        .snapshots();
  }

  Widget _summaryCardsLoadingPlaceholder() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sellers')
          .doc(widget.seller.id)
          .snapshots(),
      builder: (context, sellerSnap) {
        final creditBalance =
            (sellerSnap.data?.data()?['creditBalance'] ?? 0).toDouble();
        final creditWaiting =
            sellerSnap.connectionState == ConnectionState.waiting;
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.pending_actions,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Current Outstanding',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.shopping_cart,
                                    color: Colors.green.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Total Sale (net)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Credit Balance',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            creditWaiting
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : SelectableText(
                                    _currencyFormatter.format(creditBalance),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      if (creditBalance > 0)
                        IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.orange),
                          onPressed: () => _showReduceCreditBalanceDialog(
                              context, creditBalance),
                          tooltip: 'Reduce Credit Balance',
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _showEditCreditBalanceDialog(context, creditBalance),
                        tooltip: 'Edit Credit Balance',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _showDeleteCreditBalanceDialog(context),
                        tooltip: 'Delete Credit Balance and History',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sellerHistoryOpenDueStream(),
      builder: (context, openDueSnap) {
        if (openDueSnap.hasError) {
          return _buildLegacySummaryCardsStream();
        }
        if (!openDueSnap.hasData) {
          return _summaryCardsLoadingPlaceholder();
        }

        final allTimeOutstanding = openDueSnap.data!.docs.fold<double>(
          0.0,
          (s, d) => s + ((d.data())['duePayment'] ?? 0).toDouble(),
        );

        final hasDateRange = _startDate != null && _endDate != null;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: hasDateRange
              ? _sellerHistorySaleDateInRangeStream()
              : FirebaseFirestore.instance
                  .collection('sales')
                  .where('sellerId', isEqualTo: widget.seller.id)
                  .snapshots(),
          builder: (context, innerSnap) {
            if (innerSnap.hasError) {
              return _buildLegacySummaryCardsStream();
            }
            if (!innerSnap.hasData) {
              return _summaryCardsLoadingPlaceholder();
            }

            final periodDocs = hasDateRange
                ? innerSnap.data!.docs
                : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final saleDocsInPeriod = hasDateRange
                ? periodDocs
                    .where((d) => !_isPaymentRecord(d.data()))
                    .toList()
                : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final periodDuePaymentsReceived = hasDateRange
                ? periodDocs.fold<double>(
                    0.0,
                    (sum, doc) {
                      final data = doc.data();
                      return sum +
                          (_isPaymentRecord(data)
                              ? (data['saleAmount'] ?? 0).toDouble()
                              : 0);
                    },
                  )
                : 0.0;

            final totalSaleAllTime = !hasDateRange
                ? innerSnap.data!.docs.fold<double>(
                    0.0,
                    (s, d) {
                      try {
                        return s + Sale.fromMap(d.data()).netTotal;
                      } catch (_) {
                        return s;
                      }
                    },
                  )
                : 0.0;

            return FutureBuilder<double>(
              future: hasDateRange
                  ? _calculateTotalSaleFromActualSales(saleDocsInPeriod)
                  : Future.value(0.0),
              builder: (context, periodFut) {
                final periodSales =
                    hasDateRange ? (periodFut.data ?? 0.0) : 0.0;
                final periodLabel = hasDateRange
                    ? ' (${_dateFormatter.format(_startDate!)} - ${_dateFormatter.format(_endDate!)})'
                    : '';
                final saleWaiting = hasDateRange &&
                    periodFut.connectionState == ConnectionState.waiting;
                final totalSaleDisplay =
                    hasDateRange ? periodSales : totalSaleAllTime;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('sellers')
                      .doc(widget.seller.id)
                      .snapshots(),
                  builder: (context, sellerDocSnap) {
                    final creditBalance =
                        (sellerDocSnap.data?.data()?['creditBalance'] ?? 0)
                            .toDouble();

                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _showDuePaymentHistory(
                                      context, allTimeOutstanding),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Card(
                                    color: Colors.orange.shade50,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.pending_actions,
                                                  color:
                                                      Colors.orange.shade700),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  hasDateRange
                                                      ? 'Paid in period$periodLabel'
                                                      : 'Current Outstanding',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color:
                                                        Colors.orange.shade900,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          SelectableText(
                                            hasDateRange
                                                ? _currencyFormatter.format(
                                                    periodDuePaymentsReceived)
                                                : _currencyFormatter.format(
                                                    allTimeOutstanding),
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange.shade700,
                                            ),
                                          ),
                                          if (hasDateRange &&
                                              allTimeOutstanding > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4),
                                              child: Text(
                                                'Outstanding: ${_currencyFormatter.format(allTimeOutstanding)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      Colors.orange.shade800,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Card(
                                  color: Colors.green.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.shopping_cart,
                                                color: Colors.green.shade700),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                hasDateRange
                                                    ? 'Sales$periodLabel'
                                                    : 'Total Sale (net)',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.green.shade900,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        saleWaiting
                                            ? const SizedBox(
                                                height: 24,
                                                width: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : SelectableText(
                                                _currencyFormatter
                                                    .format(totalSaleDisplay),
                                                style: TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Card(
                            color: Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(Icons.account_balance_wallet,
                                      color: Colors.blue.shade700),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Credit Balance',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.blue.shade900,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        sellerDocSnap.connectionState ==
                                                ConnectionState.waiting
                                            ? const SizedBox(
                                                height: 24,
                                                width: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : SelectableText(
                                                _currencyFormatter
                                                    .format(creditBalance),
                                                style: TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                  if (creditBalance > 0)
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle,
                                          color: Colors.orange),
                                      onPressed: () =>
                                          _showReduceCreditBalanceDialog(
                                              context, creditBalance),
                                      tooltip: 'Reduce Credit Balance',
                                    ),
                                  IconButton(
                                    icon:
                                        const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () =>
                                        _showEditCreditBalanceDialog(
                                            context, creditBalance),
                                    tooltip: 'Edit Credit Balance',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _showDeleteCreditBalanceDialog(context),
                                    tooltip: 'Delete Credit Balance and History',
                                  ),
                                ],
                              ),
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
      },
    );
  }

  DateTime _createdAtFromHistoryData(Map<String, dynamic> data) {
    final c = data['createdAt'];
    if (c is Timestamp) return c.toDate();
    if (c is String) return DateTime.tryParse(c) ?? DateTime(1970);
    return DateTime(1970);
  }

  /// True if this seller_history record is a due payment (money received), not a sale.
  bool _isPaymentRecord(Map<String, dynamic> data) {
    if (data['recordType'] == 'payment') return true;
    final isManual = data['isManual'] == true;
    final duePayment = (data['duePayment'] ?? 0).toDouble();
    final amountPaid = (data['amountPaid'] ?? 0).toDouble();
    final saleAmount = (data['saleAmount'] ?? 0).toDouble();
    return isManual && duePayment == 0 && amountPaid == saleAmount && saleAmount > 0;
  }

  bool _isRecoveryReversalRecord(Map<String, dynamic> data) {
    return data['recordType'] == 'recovery_reversal';
  }

  /// Filter seller_history docs to those whose saleDate is within [startDate, endDate].
  List<QueryDocumentSnapshot> _filterRecordsByDateRange(
    List<QueryDocumentSnapshot> docs,
    DateTime startDate,
    DateTime endDate,
  ) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return docs.where((doc) {
      final saleDateStr = (doc.data() as Map<String, dynamic>)['saleDate'];
      if (saleDateStr == null) return false;
      final saleDate = DateTime.parse(saleDateStr);
      final d = DateTime(saleDate.year, saleDate.month, saleDate.day);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
  }

  // Calculate total sale by fetching actual sale data to account for returns
  // This uses netTotal (total - returnedAmount) to ensure returns are properly subtracted
  Future<double> _calculateTotalSaleFromActualSales(List<QueryDocumentSnapshot> records) async {
    try {
      // Get unique sale IDs from records
      final saleIds = records
          .map((doc) => (doc.data() as Map<String, dynamic>)['saleId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      if (saleIds.isEmpty) return 0.0;

      // Fetch all sales in parallel
      final saleFutures = saleIds.map((saleId) async {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('sales')
              .doc(saleId)
              .get();
          
          if (doc.exists) {
            final sale = Sale.fromMap(doc.data()!);
            // Use netTotal which is total - returnedAmount
            return sale.netTotal;
          }
          return 0.0;
        } catch (e) {
          debugPrint('Error fetching sale $saleId: $e');
          // If sale not found, fall back to seller_history.saleAmount
          final record = records.firstWhere(
            (doc) => (doc.data() as Map<String, dynamic>)['saleId'] == saleId,
            orElse: () => records.first,
          );
          final data = record.data() as Map<String, dynamic>;
          return (data['saleAmount'] ?? 0).toDouble();
        }
      });

      final saleTotals = await Future.wait(saleFutures);
      return saleTotals.fold<double>(0.0, (sum, total) => sum + total);
    } catch (e) {
      debugPrint('Error calculating total sale from actual sales: $e');
      // Fallback to using seller_history.saleAmount if there's an error
      return records.fold<double>(
        0.0,
        (sum, doc) {
          final data = doc.data() as Map<String, dynamic>;
          return sum + (data['saleAmount'] ?? 0).toDouble();
        },
      );
    }
  }

  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _selectStartDate(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _startDate != null
                            ? _dateFormatter.format(_startDate!)
                            : 'Start Date',
                        style: TextStyle(
                          color: _startDate != null
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                    if (_startDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _startDate = null;
                          });
                          _onSellerHistoryDateFilterChanged();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _selectEndDate(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _endDate != null
                            ? _dateFormatter.format(_endDate!)
                            : 'End Date',
                        style: TextStyle(
                          color: _endDate != null
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                    if (_endDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _endDate = null;
                          });
                          _onSellerHistoryDateFilterChanged();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isGeneratingPdf ? null : () => _createAndShowPdf(context),
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf, size: 20),
            label: Text(_isGeneratingPdf ? 'Generating...' : 'Create PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  bool _isGeneratingPdf = false;

  Future<void> _createAndShowPdf(BuildContext context) async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both Start Date and End Date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_startDate!.isAfter(_endDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date must be before end date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      Uint8List pdfBytes;
      final isCreditTab = _tabController.index == 1;

      if (isCreditTab) {
        // Credit History tab: generate separate Credit History PDF
        final creditHistory = await _sellerService.getCreditHistory(
          widget.seller.id,
          startDate: _startDate,
          endDate: _endDate,
        );
        pdfBytes = await _generateCreditHistoryPdf(creditHistory);
      } else {
        // Sales History tab: generate Seller/Sales History PDF
        final history = await _fetchFilteredHistory();
        pdfBytes = await _generateSellerHistoryPdf(history);
      }

      if (!context.mounted) return;
      setState(() => _isGeneratingPdf = false);

      await _showPdfOptionsDialog(context, pdfBytes, isCreditHistory: isCreditTab);
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchFilteredHistory() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('seller_history')
        .where('sellerId', isEqualTo: widget.seller.id)
        .get();

    var records = snapshot.docs.map((doc) {
      final data = doc.data();
      return {...data, 'id': doc.id};
    }).toList();

    final startOnly = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
    final endOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);

    records = records.where((record) {
      final saleDateStr = record['saleDate'];
      if (saleDateStr == null) return false;
      final saleDate = DateTime.parse(saleDateStr);
      final saleDateOnly = DateTime(saleDate.year, saleDate.month, saleDate.day);
      return !saleDateOnly.isBefore(startOnly) && !saleDateOnly.isAfter(endOnly);
    }).toList();

    // Sort by date ASCENDING (oldest first) - day-wise for easy checking
    records.sort((a, b) {
      final aDate = a['saleDate'] != null ? DateTime.parse(a['saleDate']) : DateTime(1970);
      final bDate = b['saleDate'] != null ? DateTime.parse(b['saleDate']) : DateTime(1970);
      return aDate.compareTo(bDate); // Ascending: Day 1, Day 2, Day 3
    });

    return records;
  }

  Future<Uint8List> _generateSellerHistoryPdf(List<Map<String, dynamic>> history) async {
    final pdf = pw.Document();
    final dateRangeStr = '${_dateFormatter.format(_startDate!)} - ${_dateFormatter.format(_endDate!)}';
    final generatedAt = DateTime.now();

    // Live total due — same as "Current Outstanding" on the seller screen.
    final currentTotalDue =
        await _sellerService.getTotalDueAmountForSeller(widget.seller.id);

    // Resolve record type for existing data:
    // - payment: manual due payment recovery
    // - recovery_reversal: due re-opened after return refund
    // - sale: normal sale/manual sale
    final resolvedTypes = <int, String>{}; // index -> 'payment' | 'recovery_reversal' | 'sale'
    for (int i = 0; i < history.length; i++) {
      final record = history[i];
      final recordType = (record['recordType'] as String?)?.trim();
      if (recordType == 'recovery_reversal') {
        resolvedTypes[i] = 'recovery_reversal';
        continue;
      }
      if (recordType == 'payment') {
        resolvedTypes[i] = 'payment';
        continue;
      }
      final isManual = record['isManual'] == true;
      final duePayment = (record['duePayment'] ?? 0).toDouble();
      final saleAmount = (record['saleAmount'] ?? 0).toDouble();
      final amountPaid = (record['amountPaid'] ?? 0).toDouble();
      final saleId = record['saleId'] as String?;

      bool isPayment = false;
      if (isManual && duePayment == 0 && amountPaid == saleAmount && saleAmount > 0 && saleId != null && saleId.isNotEmpty) {
        try {
          final saleDoc = await FirebaseFirestore.instance.collection('sales').doc(saleId).get();
          if (saleDoc.exists) {
            final saleData = saleDoc.data();
            final saleTotal = (saleData?['total'] ?? 0).toDouble();
            final items = saleData?['items'] as List<dynamic>?;
            // Manual payment: Sale has total=0, no items (recovery only)
            isPayment = saleTotal == 0 && (items == null || items.isEmpty);
          }
        } catch (_) {
          // On error, treat as Sale for safety
        }
      }

      resolvedTypes[i] = isPayment ? 'payment' : 'sale';
    }

    // POS stores full cash + recovery on [sales/]; seller_history [amountPaid] is only to this bill.
    final saleIdsForPdf = <String>{};
    for (int i = 0; i < history.length; i++) {
      final rt = resolvedTypes[i] ?? 'sale';
      if (rt == 'payment' || rt == 'recovery_reversal') continue;
      final sid = history[i]['saleId'] as String? ?? '';
      if (sid.isNotEmpty) saleIdsForPdf.add(sid);
    }
    final salesByIdForPdf = await _loadSalesMapForPdf(saleIdsForPdf);

    // Unclamped net of all rows in this PDF (Debit − Credit) so that:
    // opening + net = current total due (same as app Current Outstanding).
    double netFromRangeRows = 0.0;
    for (int i = 0; i < history.length; i++) {
      final record = history[i];
      final saleAmount = (record['saleAmount'] ?? 0).toDouble();
      final amountPaid = (record['amountPaid'] ?? 0).toDouble();
      final duePayment = (record['duePayment'] ?? 0).toDouble();
      final saleIdRow = record['saleId'] as String? ?? '';
      final rowType = resolvedTypes[i] ?? 'sale';
      final isPaymentRecord = rowType == 'payment';
      final isRecoveryReversal = rowType == 'recovery_reversal';
      if (isPaymentRecord || isRecoveryReversal) {
        final debitAmount = isRecoveryReversal ? duePayment : 0.0;
        final creditAmount = isRecoveryReversal ? 0.0 : saleAmount;
        netFromRangeRows += debitAmount - creditAmount;
      } else {
        final sd = saleIdRow.isNotEmpty ? salesByIdForPdf[saleIdRow] : null;
        final credit = _ledgerTotalCreditForSalePdf(sd, amountPaid);
        netFromRangeRows += saleAmount - credit;
      }
    }
    final correctOpening = currentTotalDue - netFromRangeRows;

    double totalSalesAmount = 0;
    double totalPaymentsReceived = 0;
    double totalDueOutstanding = 0;
    double totalLedgerDebit = 0;
    double totalLedgerCredit = 0;

    double runningDueBalance = correctOpening;

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Date/Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('V.Type', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Debit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Credit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Balance', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
        ],
      ),
    ];

    // Opening balance row (previous dues before selected range)
    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              _dateFormatter.format(_startDate!),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              'OB',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('-', style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              'Opening balance',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: correctOpening > 0
                ? pw.Text(
                    _currencyFormatter.format(correctOpening),
                    style: const pw.TextStyle(fontSize: 8),
                  )
                : pw.Text('-', style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('-', style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              '${_currencyFormatter.format(runningDueBalance)} DR',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    for (int i = 0; i < history.length; i++) {
      final record = history[i];
      final saleAmount = (record['saleAmount'] ?? 0).toDouble();
      final amountPaid = (record['amountPaid'] ?? 0).toDouble();
      final duePayment = (record['duePayment'] ?? 0).toDouble();
      final saleId = record['saleId'] ?? '';
      final saleDateStr = record['saleDate'];
      final saleDate = saleDateStr != null ? DateTime.parse(saleDateStr) : null;
      final referenceNumber = record['referenceNumber'] as String?;
      final saleDescriptionPdf = record['description'] as String?;
      String pdfRefCell() {
        final parts = <String>[];
        if (referenceNumber != null && referenceNumber.trim().isNotEmpty) {
          parts.add(referenceNumber.trim());
        }
        if (saleDescriptionPdf != null && saleDescriptionPdf.trim().isNotEmpty) {
          parts.add(saleDescriptionPdf.trim());
        }
        if (parts.isEmpty) return '-';
        // ASCII separator: PDF built-in fonts often fail on middle-dot / em-dash.
        return parts.join(' | ');
      }

      final refCellText = pdfRefCell();
      final rowType = resolvedTypes[i] ?? 'sale';
      final isPaymentRecord = rowType == 'payment';
      final isRecoveryReversal = rowType == 'recovery_reversal';
      final shortSaleId = saleId.length >= 8 ? saleId.substring(0, 8).toUpperCase() : saleId;

      if (isPaymentRecord || isRecoveryReversal) {
        // Ledger style:
        // - Payment: credit (reduces due)
        // - Recovery reversal: debit (re-opens due after return)
        final debitAmount = isRecoveryReversal ? duePayment : 0.0;
        final creditAmount = isRecoveryReversal ? 0.0 : saleAmount;
        totalLedgerDebit += debitAmount;
        totalLedgerCredit += creditAmount;
        runningDueBalance += debitAmount;
        runningDueBalance -= creditAmount;

        if (isPaymentRecord) totalPaymentsReceived += saleAmount;

        tableRows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isRecoveryReversal ? PdfColors.orange50 : PdfColors.green50,
            ),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(saleDate != null ? _dateTimeFormatter.format(saleDate) : '-', style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  isRecoveryReversal ? 'RV' : 'CR',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: isRecoveryReversal ? PdfColors.orange800 : PdfColors.green800,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(isRecoveryReversal ? shortSaleId : '-', style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  isRecoveryReversal ? 'Recovery reversed due to return' : 'Applied to dues',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  debitAmount > 0 ? _currencyFormatter.format(debitAmount) : '-',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: isRecoveryReversal ? PdfColors.orange800 : PdfColors.green800,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  creditAmount > 0 ? _currencyFormatter.format(creditAmount) : '-',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  '${_currencyFormatter.format(runningDueBalance)} DR',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        );
      } else {
        // Sale ledger model:
        // - Debit = full sale amount (new charge)
        // - Credit = full amount paid in this sale entry
        //   (if paid > sale, extra payment naturally reduces old dues here).
        final balanceBeforeSale = runningDueBalance;
        final debitAmount = saleAmount;
        final saleDoc = saleId.isNotEmpty ? salesByIdForPdf[saleId] : null;
        // Full payment reducing due: cash (minus change) + wallet; matches POS receipt.
        final creditOnCurrentSale = _ledgerTotalCreditForSalePdf(saleDoc, amountPaid);
        final totalOwedBeforeCash = balanceBeforeSale + saleAmount;
        // "This bill" / old split: from sales doc when POS (accurate for pay 20 on bill 5).
        final fullCashIn = (saleDoc?['amountPaid'] as num?)?.toDouble() ?? 0.0;
        final changeOut = (saleDoc?['change'] as num?)?.toDouble() ?? 0.0;
        final creditWallet = (saleDoc?['creditUsed'] as num?)?.toDouble() ?? 0.0;
        final recoveryToOld = (saleDoc?['recoveryBalance'] as num?)?.toDouble() ?? 0.0;
        // seller_history [amountPaid] = total applied to *this* sale line (cash + credit to bill).
        final toThisBill = amountPaid;
        final returnedAmt = (saleDoc?['returnedAmount'] as num?)?.toDouble() ?? 0.0;
        final grossBill = (saleDoc?['total'] as num?)?.toDouble() ?? 0.0;
        final descChildren = <pw.Widget>[];
        if (refCellText == '-') {
          final line1 =
              'Prev ${balanceBeforeSale < 0 ? _currencyFormatter.format(0) : _currencyFormatter.format(balanceBeforeSale)} + Bill ${_currencyFormatter.format(saleAmount)} = Total ${_currencyFormatter.format(totalOwedBeforeCash)}';
          descChildren.add(pw.Text(line1, style: const pw.TextStyle(fontSize: 7)));
          if (creditOnCurrentSale > 0 || fullCashIn > 0 || creditWallet > 0) {
            final parts = <String>[];
            if (fullCashIn > 0) {
              parts.add(
                changeOut > 0
                    ? 'Cash in ${_currencyFormatter.format(fullCashIn)} (back ${_currencyFormatter.format(changeOut)})'
                    : 'Cash in ${_currencyFormatter.format(fullCashIn)}',
              );
            }
            if (creditWallet > 0) {
              parts.add('Wallet ${_currencyFormatter.format(creditWallet)}');
            }
            if (parts.isEmpty && toThisBill > 0) {
              parts.add('To this bill ${_currencyFormatter.format(toThisBill)}');
            }
            final head = parts.isNotEmpty ? parts.join(' | ') : '';
            final split = recoveryToOld > 0
                ? 'This bill: ${_currencyFormatter.format(toThisBill)} | Old dues: ${_currencyFormatter.format(recoveryToOld)}'
                : 'This bill: ${_currencyFormatter.format(toThisBill)}';
            descChildren.add(
              pw.Text(
                head.isNotEmpty ? '$head - $split' : split,
                style: const pw.TextStyle(fontSize: 6),
              ),
            );
          }
        } else {
          final extra = creditOnCurrentSale > 0
              ? (fullCashIn > 0
                  ? 'Cash ${_currencyFormatter.format(fullCashIn)} (this bill ${_currencyFormatter.format(toThisBill)}'
                      '${recoveryToOld > 0 ? ' | old ${_currencyFormatter.format(recoveryToOld)}' : ''})'
                  : 'This bill ${_currencyFormatter.format(toThisBill)}'
                      '${recoveryToOld > 0 ? ' | old ${_currencyFormatter.format(recoveryToOld)}' : ''}')
              : '';
          descChildren.add(pw.Text(refCellText, style: const pw.TextStyle(fontSize: 7)));
          if (creditOnCurrentSale > 0) {
            descChildren.add(
              pw.Text(
                'Prev+Bill Total ${_currencyFormatter.format(totalOwedBeforeCash)}. $extra',
                style: const pw.TextStyle(fontSize: 6),
              ),
            );
          } else {
            descChildren.add(
              pw.Text(
                'Prev+Bill Total ${_currencyFormatter.format(totalOwedBeforeCash)}',
                style: const pw.TextStyle(fontSize: 6),
              ),
            );
          }
        }
        if (returnedAmt > 0.001) {
          final retNote = grossBill > 0
              ? 'Item return: ${_currencyFormatter.format(returnedAmt)} (gross was ${_currencyFormatter.format(grossBill)}; Debit column is net after return)'
              : 'Item return: ${_currencyFormatter.format(returnedAmt)} (Debit column is net after return)';
          descChildren.add(
            pw.Text(
              retNote,
              style: const pw.TextStyle(fontSize: 6),
            ),
          );
        }
        final saleDescCell = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: descChildren,
        );
        totalLedgerDebit += debitAmount;
        totalLedgerCredit += creditOnCurrentSale;
        runningDueBalance += debitAmount;
        runningDueBalance -= creditOnCurrentSale;

        totalSalesAmount += saleAmount;
        totalDueOutstanding += duePayment;
        tableRows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(saleDate != null ? _dateTimeFormatter.format(saleDate) : '-', style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('SV', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(shortSaleId, style: const pw.TextStyle(fontSize: 8)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: saleDescCell,
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  debitAmount > 0 ? _currencyFormatter.format(debitAmount) : '-',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  creditOnCurrentSale > 0
                      ? _currencyFormatter.format(creditOnCurrentSale)
                      : '-',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  '${_currencyFormatter.format(runningDueBalance)} DR',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        );
      }
    }

    // Must match app "Current Outstanding" (same source as [currentTotalDue]).
    final closingDueFromLedger = currentTotalDue;

    // Explicit final balance row at end of ledger entries.
    tableRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              _dateTimeFormatter.format(DateTime.now()),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              'FB',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              '-',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              'Final Balance',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              '-',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              '-',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
                  '${_currencyFormatter.format(closingDueFromLedger)} DR',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Seller Ledger History', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Party: ${widget.seller.name}', style: const pw.TextStyle(fontSize: 11)),
                if (widget.seller.phone != null && widget.seller.phone!.isNotEmpty)
                  pw.Text('Phone: ${widget.seller.phone}', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('From: ${_dateFormatter.format(_startDate!)}    To: ${_dateFormatter.format(_endDate!)}', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Generated: ${_dateTimeFormatter.format(generatedAt)}', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Ledger: Debit +, Credit -. Opening = Current Outstanding − net of rows below, so the last row matches the app total due.',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Legend: OB = Opening | SV = Sale (Debit = net bill after any item return) | CR = Payment | RV = Recovery reversed if return refund re-opened old due',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.8),
              1: const pw.FlexColumnWidth(0.8),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(2.1),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
              6: const pw.FlexColumnWidth(1.2),
            },
            children: tableRows,
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Date Range: $dateRangeStr | ARS Traders',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> _generateCreditHistoryPdf(List<CreditHistory> creditHistory) async {
    final pdf = pw.Document();
    final dateRangeStr = '${_dateFormatter.format(_startDate!)} - ${_dateFormatter.format(_endDate!)}';

    final creditBalance = await _sellerService.getCreditBalance(widget.seller.id);
    double totalAdded = 0;
    double totalReduced = 0;
    for (final h in creditHistory) {
      if (h.amount > 0) {
        totalAdded += h.amount;
      } else {
        totalReduced += h.amount.abs();
      }
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Date & Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Type', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Before', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('After', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    ];

    for (final h in creditHistory) {
      final isPositive = h.amount > 0;
      final typeLabel = isPositive ? 'Credit Added' : 'Credit Reduced';
      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isPositive ? PdfColors.green50 : PdfColors.orange50,
          ),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(_dateTimeFormatter.format(h.createdAt), style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                typeLabel,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: isPositive ? PdfColors.green800 : PdfColors.orange800,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(_currencyFormatter.format(h.balanceBefore), style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(_currencyFormatter.format(h.balanceAfter), style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                '${isPositive ? '+' : '-'}${_currencyFormatter.format(h.amount.abs())}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: isPositive ? PdfColors.green800 : PdfColors.orange800,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(h.description ?? '-', style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Credit History Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(widget.seller.name, style: const pw.TextStyle(fontSize: 14)),
                pw.Text('Date Range: $dateRangeStr', style: const pw.TextStyle(fontSize: 10)),
                if (widget.seller.phone != null && widget.seller.phone!.isNotEmpty)
                  pw.Text('Phone: ${widget.seller.phone}', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Credit transactions (added/reduced) in chronological order.',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Credit Balance', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(_currencyFormatter.format(creditBalance), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Added (Period)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(_currencyFormatter.format(totalAdded), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Reduced (Period)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(_currencyFormatter.format(totalReduced), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(2),
            },
            children: tableRows,
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Generated on ${_dateTimeFormatter.format(DateTime.now())} | ARS Traders',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  String _formatPhoneForWhatsApp(String? phone) {
    if (phone == null || phone.trim().isEmpty) return '';
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+92')) {
      return cleaned.substring(1); // Remove + for wa.me
    }
    if (cleaned.startsWith('92')) {
      return cleaned;
    }
    if (cleaned.startsWith('0')) {
      return '92${cleaned.substring(1)}';
    }
    return '92$cleaned';
  }

  Future<void> _sendPdfViaWhatsApp(
    BuildContext context,
    BuildContext dialogContext,
    Uint8List pdfBytes,
    String filename, {
    bool isCreditHistory = false,
  }) async {
    final sellerPhone = _formatPhoneForWhatsApp(widget.seller.phone);
    if (sellerPhone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seller phone number not found. Cannot send via WhatsApp.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    Navigator.pop(dialogContext);

    try {
      final whatsappUrl = Uri.parse('https://wa.me/$sellerPhone');

      if (kIsWeb) {
        // Chrome/Web: Share first (Web Share API shows share sheet with file), then open seller chat
        final xFile = XFile.fromData(
          pdfBytes,
          mimeType: 'application/pdf',
          name: filename,
        );
        final reportLabel = isCreditHistory ? 'Credit History Report' : 'Seller History Report';
        await Share.shareXFiles(
          [xFile],
          text: '$reportLabel - ${widget.seller.name}',
        );
        try {
          await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
        } catch (_) {}
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Share sheet shown. Pick WhatsApp to send PDF with file attached. Seller chat opens next.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        // Android/iOS: Share PDF directly to seller's WhatsApp with file pre-attached
        final reportLabel = isCreditHistory ? 'Credit History Report' : 'Seller History Report';
        final success = await whatsapp_share.sharePdfToWhatsAppContact(
          sellerPhone,
          pdfBytes,
          filename,
          widget.seller.name,
          reportLabel: reportLabel,
        );
        if (success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('WhatsApp opened with PDF attached to seller\'s chat.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          // Fallback: WhatsApp not installed - use generic share + wa.me
          final xFile = XFile.fromData(
            pdfBytes,
            mimeType: 'application/pdf',
            name: filename,
          );
          await Share.shareXFiles(
            [xFile],
            text: '$reportLabel - ${widget.seller.name}',
          );
          if (await canLaunchUrl(whatsappUrl)) {
            await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Share sheet shown. Select WhatsApp to send. Opening seller chat...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showPdfOptionsDialog(BuildContext context, Uint8List pdfBytes, {bool isCreditHistory = false}) async {
    final prefix = isCreditHistory ? 'credit_history' : 'seller_history';
    final filename = '${prefix}_${widget.seller.name.replaceAll(' ', '_')}_${_dateFormatter.format(_startDate!)}_${_dateFormatter.format(_endDate!)}.pdf'
        .replaceAll(RegExp(r'[^\w\-\.]'), '_');

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            SizedBox(width: 12),
            Text('PDF Ready'),
          ],
        ),
        content: Text(
          isCreditHistory
              ? 'Credit history PDF has been generated. View or download it.'
              : 'Seller history PDF has been generated. View or download it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (widget.seller.phone != null && widget.seller.phone!.trim().isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _sendPdfViaWhatsApp(context, dialogContext, pdfBytes, filename, isCreditHistory: isCreditHistory),
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('Send WhatsApp'),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
            },
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('View'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (kIsWeb) {
                pdf_download.downloadPdf(pdfBytes, filename);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Downloaded: $filename'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                final xFile = XFile.fromData(
                  pdfBytes,
                  mimeType: 'application/pdf',
                  name: filename,
                );
                await Share.shareXFiles([xFile], text: isCreditHistory ? 'Credit History Report' : 'Seller History Report');
              }
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_sellerHistoryIsAllTimeMode) {
      return _buildHistoryListPaginated();
    }
    return _buildHistoryListStream();
  }

  Widget _buildHistoryListPaginated() {
    if (_paginatedSellerHistoryError != null &&
        _paginatedSellerHistory.isEmpty &&
        !_paginatedSellerHistoryInitialLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Error: ${_paginatedSellerHistoryError}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _resetAndLoadSellerHistoryPage(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_paginatedSellerHistoryInitialLoading &&
        _paginatedSellerHistory.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_paginatedSellerHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No history found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'No transactions recorded yet',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _paginatedSellerHistory.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSalesHistoryLegendCard();
        }
        if (index == _paginatedSellerHistory.length + 1) {
          if (_paginatedSellerHistoryLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (_paginatedSellerHistoryHasMore) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => _fetchSellerHistoryPage(append: true),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 8),
            child: Center(
              child: Text(
                'End of history',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          );
        }
        return _salesHistoryListCard(
            context, _paginatedSellerHistory[index - 1]);
      },
    );
  }

  Widget _buildHistoryListStream() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getHistoryStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final history = snapshot.data ?? [];
        final partialDateRange =
            (_startDate != null) != (_endDate != null);
        final showRecentCapHint = partialDateRange && history.length >= 500;

        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No history found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _startDate != null || _endDate != null
                      ? 'Try adjusting your date filter'
                      : 'No transactions recorded yet',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: history.length + (showRecentCapHint ? 1 : 0) + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildSalesHistoryLegendCard();
            }
            if (showRecentCapHint && index == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade900, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Showing the 500 most recent rows by sale date. '
                            'Pick start and end dates above to load a specific period from the server.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            final record = history[showRecentCapHint ? index - 2 : index - 1];
            return _salesHistoryListCard(context, record);
          },
        );
      },
    );
  }

  Widget _buildSalesHistoryLegendCard() {
    Widget legendItem({
      required Color background,
      required Color border,
      required Color text,
      required String label,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'History Legend',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  legendItem(
                    background: Colors.blue.shade100,
                    border: Colors.blue.shade300,
                    text: Colors.blue.shade900,
                    label: 'Paid Toward This Sale',
                  ),
                  legendItem(
                    background: Colors.orange.shade100,
                    border: Colors.orange.shade300,
                    text: Colors.orange.shade900,
                    label: 'New Due / Pending',
                  ),
                  legendItem(
                    background: Colors.green.shade100,
                    border: Colors.green.shade300,
                    text: Colors.green.shade900,
                    label: 'Due Payment Recovery',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _salesHistoryListCard(
    BuildContext context,
    Map<String, dynamic> record,
  ) {
    final saleAmount = (record['saleAmount'] ?? 0).toDouble();
    final amountPaid = (record['amountPaid'] ?? 0).toDouble();
    final duePayment = (record['duePayment'] ?? 0).toDouble();
    final saleDate = record['saleDate'] != null
        ? DateTime.parse(record['saleDate'])
        : null;
    final saleId = record['saleId'] ?? '';
    final referenceNumber = record['referenceNumber'] as String?;
    final saleDescriptionNote = record['description'] as String?;
    final isManual = record['isManual'] == true;
    final isRecoveryReversalRecord = _isRecoveryReversalRecord(record);
    final isPaymentRecord = _isPaymentRecord(record);
    final isPaymentLikeRecord = isPaymentRecord || isRecoveryReversalRecord;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isRecoveryReversalRecord
              ? Colors.deepOrange.shade100
              : (isPaymentLikeRecord || duePayment <= 0
                  ? Colors.green.shade100
                  : Colors.orange.shade100),
          child: Icon(
            isRecoveryReversalRecord
                ? Icons.assignment_return
                : (isPaymentLikeRecord
                    ? Icons.payment
                    : (duePayment > 0 ? Icons.pending : Icons.check_circle)),
            color: isRecoveryReversalRecord
                ? Colors.deepOrange.shade700
                : (isPaymentLikeRecord || duePayment <= 0
                    ? Colors.green.shade700
                    : Colors.orange.shade700),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SelectableText(
                    isPaymentLikeRecord
                        ? (isRecoveryReversalRecord
                            ? 'Recovery Reversal'
                            : 'Payment')
                        : 'Sale #${saleId.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isManual && saleId.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isPaymentLikeRecord) ...[
                        IconButton(
                          icon: const Icon(Icons.edit,
                              color: Colors.blue, size: 18),
                          onPressed: () => _showEditManualSaleDialog(
                            context,
                            saleId: saleId,
                            saleAmount: saleAmount,
                            amountPaid: amountPaid,
                            saleDate: saleDate,
                            referenceNumber: referenceNumber,
                          ),
                          tooltip: 'Edit Manual Sale',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.red, size: 18),
                          onPressed: () => _showDeleteManualSaleDialog(
                            context,
                            saleId,
                            saleAmount,
                            duePayment,
                          ),
                          tooltip: 'Delete Manual Sale',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        tooltip: 'Receipt options',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onSelected: (value) async {
                          if (value == 'print_receipt') {
                            await _handleManualHistoryReceiptPrint(
                                context, saleId);
                          } else if (value == 'view_pdf') {
                            await _handleManualHistoryReceiptViewPdf(
                                context, saleId);
                          } else if (value == 'download_pdf') {
                            await _handleManualHistoryReceiptDownloadPdf(
                                context, saleId);
                          }
                        },
                        itemBuilder: (ctx) => [
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
                    ],
                  ),
                if (saleDate != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SelectableText(
                      _dateTimeFormatter.format(saleDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPaymentLikeRecord)
                      SelectableText(
                        _currencyFormatter.format(
                          isRecoveryReversalRecord ? duePayment : amountPaid,
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else ...[
                      SelectableText(
                        'Sale Amount: ${_currencyFormatter.format(saleAmount)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      SelectableText(
                        'Paid Toward This Sale: ${_currencyFormatter.format(amountPaid)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      if (duePayment > 0)
                        SelectableText(
                          'New Due From This Sale: ${_currencyFormatter.format(duePayment)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                    if (referenceNumber != null && referenceNumber.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(
                          'Reference: $referenceNumber',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                      ),
                    ),
                    if (saleDescriptionNote != null &&
                        saleDescriptionNote.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(
                          'Description: $saleDescriptionNote',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                if (duePayment > 0 && !isPaymentLikeRecord)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200!),
                    ),
                    child: SelectableText(
                      'Due: ${_currencyFormatter.format(duePayment)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  )
                else if (isPaymentLikeRecord || duePayment <= 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isRecoveryReversalRecord
                          ? Colors.deepOrange.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRecoveryReversalRecord
                            ? Colors.deepOrange.shade200
                            : Colors.green.shade200!,
                      ),
                    ),
                    child: Text(
                      isRecoveryReversalRecord ? 'Re-opened Due' : 'Paid',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isRecoveryReversalRecord
                            ? Colors.deepOrange.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            isPaymentLikeRecord
                ? (isRecoveryReversalRecord
                    ? 'Recovery reversal from item return (due re-opened)'
                    : 'Due payment record (applies to older unpaid sales)')
                : 'Sale record (shows this bill only)',
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),
        children: isPaymentLikeRecord
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRecoveryReversalRecord
                            ? 'Return refund reversed recovered cash: ${_currencyFormatter.format(duePayment)} re-opened in outstanding due.'
                            : 'Payment of ${_currencyFormatter.format(amountPaid)} applied to previous unpaid sales (oldest first).',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (referenceNumber != null && referenceNumber.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Reference: $referenceNumber',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (saleDescriptionNote != null &&
                          saleDescriptionNote.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Description: $saleDescriptionNote',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ]
            : [
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('sales')
                .doc(saleId)
                .get(),
            builder: (context, saleSnapshot) {
              if (saleSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (!saleSnapshot.hasData || !saleSnapshot.data!.exists) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Sale details not found',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              try {
                final saleData = saleSnapshot.data!.data()
                    as Map<String, dynamic>;
                final sale = Sale.fromMap(saleData);

                if (sale.items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No items found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300!),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Total Amount at Top
                      Center(
                        child: SelectableText(
                          _currencyFormatter.format(sale.total),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Date, Items, Payment Method, Profit
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            radius: 20,
                            child: Icon(
                              Icons.receipt,
                              color: Colors.green.shade700,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (saleDate != null)
                                  Text(
                                    _dateTimeFormatter.format(saleDate),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  '${sale.items.length} item(s) • ${sale.paymentMethod}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (_showSellerHistoryProfit)
                                  SelectableText(
                                    'Profit: ${_currencyFormatter.format(sale.netProfit)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                if (sale.description != null &&
                                    sale.description!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    'Description: ${sale.description}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const Divider(height: 24),
                      
                      // Items Heading
                      const Text(
                        'Items:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Items List
                      ...sale.items.map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: SelectableText(
                                  '${item.productName} x${item.quantity.toStringAsFixed(3)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              SelectableText(
                                _currencyFormatter.format(item.subtotal),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      
                      const Divider(height: 24),
                      
                      // Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SelectableText(
                            _currencyFormatter.format(sale.total),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      
                      if (_showSellerHistoryProfit) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Net Profit:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SelectableText(
                              _currencyFormatter.format(sale.netProfit),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              } catch (e) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading items: $e',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCreditHistoryList() {
    return StreamBuilder<List<CreditHistory>>(
      stream: _sellerService.getCreditHistoryStream(widget.seller.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var creditHistory = snapshot.data ?? [];

        // Apply date filter
        if (_startDate != null || _endDate != null) {
          creditHistory = creditHistory.where((record) {
            final recordDate = DateTime(
              record.createdAt.year,
              record.createdAt.month,
              record.createdAt.day,
            );
            
            if (_startDate != null) {
              final startDateOnly = DateTime(
                _startDate!.year,
                _startDate!.month,
                _startDate!.day,
              );
              if (recordDate.isBefore(startDateOnly)) return false;
            }
            
            if (_endDate != null) {
              final endDateOnly = DateTime(
                _endDate!.year,
                _endDate!.month,
                _endDate!.day,
              );
              if (recordDate.isAfter(endDateOnly)) return false;
            }
            
            return true;
          }).toList();
        }

        if (creditHistory.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No credit history found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _startDate != null || _endDate != null
                      ? 'Try adjusting your date filter'
                      : 'No credit transactions recorded yet',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: creditHistory.length,
          itemBuilder: (context, index) {
            final history = creditHistory[index];
            final isPositive = history.amount > 0;
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: isPositive
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  child: Icon(
                    isPositive ? Icons.add : Icons.remove,
                    color: isPositive
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
                title: Text(
                  isPositive ? 'Credit Added' : 'Credit Reduced',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    SelectableText(
                      _dateTimeFormatter.format(history.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Before: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _currencyFormatter.format(history.balanceBefore),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'After: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _currencyFormatter.format(history.balanceAfter),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (history.description != null && history.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        history.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (history.referenceNumber != null && history.referenceNumber!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(
                        'Reference: ${history.referenceNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
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
                    color: isPositive
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isPositive
                          ? Colors.green.shade200!
                          : Colors.orange.shade200!,
                    ),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${_currencyFormatter.format(history.amount.abs())}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isPositive
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _getHistoryStream() {
    final sellerId = widget.seller.id;
    final hasFullRange = _startDate != null && _endDate != null;

    final Stream<QuerySnapshot<Map<String, dynamic>>> snapStream;
    if (hasFullRange) {
      snapStream = _sellerHistorySaleDateInRangeStream();
    } else {
      snapStream = FirebaseFirestore.instance
          .collection('seller_history')
          .where('sellerId', isEqualTo: sellerId)
          .orderBy('saleDate', descending: true)
          .limit(500)
          .snapshots();
    }

    return snapStream.map((snapshot) {
      var records = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          ...data,
          'id': doc.id,
        };
      }).toList();

      if (!hasFullRange && (_startDate != null || _endDate != null)) {
        records = records.where((record) {
          final saleDateStr = record['saleDate'];
          if (saleDateStr == null) return false;
          final saleDate = DateTime.parse(saleDateStr);
          final saleDateOnly =
              DateTime(saleDate.year, saleDate.month, saleDate.day);
          if (_startDate != null) {
            final startDateOnly = DateTime(
              _startDate!.year,
              _startDate!.month,
              _startDate!.day,
            );
            if (saleDateOnly.isBefore(startDateOnly)) return false;
          }
          if (_endDate != null) {
            final endDateOnly = DateTime(
              _endDate!.year,
              _endDate!.month,
              _endDate!.day,
            );
            if (saleDateOnly.isAfter(endDateOnly)) return false;
          }
          return true;
        }).toList();
      }

      records.sort((a, b) {
        final aDate = a['saleDate'] != null
            ? DateTime.parse(a['saleDate'])
            : DateTime(1970);
        final bDate = b['saleDate'] != null
            ? DateTime.parse(b['saleDate'])
            : DateTime(1970);
        return bDate.compareTo(aDate);
      });

      return records;
    });
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
        // If end date is before start date, clear it
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      });
      _onSellerHistoryDateFilterChanged();
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
      });
      _onSellerHistoryDateFilterChanged();
    }
  }

  void _showDuePaymentHistory(BuildContext context, double totalDue) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Due Payment History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.add_circle, color: Colors.orange.shade700),
                    onPressed: () => _showAddManualDuePaymentDialog(context),
                    tooltip: 'Add Manual Due Payment',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Due:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SelectableText(
                      _currencyFormatter.format(totalDue),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Add Manual Due Payment Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddManualDuePaymentDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Manual Due Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _sellerHistoryOpenDueStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final duePayments = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                      snapshot.data?.docs ?? [],
                    )..sort((a, b) {
                        final aDate = _createdAtFromHistoryData(a.data());
                        final bDate = _createdAtFromHistoryData(b.data());
                        return bDate.compareTo(aDate);
                      });

                    if (duePayments.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
                            const SizedBox(height: 16),
                            const Text(
                              'No due payments',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'All payments are cleared',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: duePayments.length,
                      itemBuilder: (context, index) {
                        final doc = duePayments[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final saleAmount = (data['saleAmount'] ?? 0).toDouble();
                        final amountPaid = (data['amountPaid'] ?? 0).toDouble();
                        final duePayment = (data['duePayment'] ?? 0).toDouble();
                        final saleDate = data['saleDate'] != null
                            ? DateTime.parse(data['saleDate'])
                            : null;
                        final saleId = data['saleId'] ?? '';
                        final referenceNumber = data['referenceNumber'] as String?;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Icon(
                                Icons.pending,
                                color: Colors.orange.shade700,
                              ),
                            ),
                            title: Text(
                              'Sale #${saleId.substring(0, 8).toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (saleDate != null)
                                  SelectableText(
                                    _dateTimeFormatter.format(saleDate),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  'Sale: ${_currencyFormatter.format(saleAmount)} • Paid: ${_currencyFormatter.format(amountPaid)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (referenceNumber != null && referenceNumber.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: SelectableText(
                                      'Reference: $referenceNumber',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200!),
                              ),
                              child: SelectableText(
                                _currencyFormatter.format(duePayment),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thermal print (same path as POS / sales history). [sale] must include correct [Sale.existingDueTotalAtSale].
  Future<void> _printThermalReceiptForSeller(BuildContext context, Sale sale) async {
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
                'Set up your thermal printer from the POS screen, then try again.',
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

      if (!context.mounted) return;
      final lang = await printerService.getReceiptLanguage();
      final success = await printerService.printReceipt(
        sale,
        sale.existingDueTotalAtSale,
        widget.seller,
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
        if (kIsWeb && connectionType == PrinterConnectionType.bluetooth) {
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
      debugPrint('Seller history print receipt: $e');
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

  Future<void> _handleManualHistoryReceiptPrint(
      BuildContext context, String saleId) async {
    final sale = await _salesService.getSaleById(saleId);
    if (!context.mounted) return;
    if (sale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await _printThermalReceiptForSeller(context, sale);
  }

  Future<void> _handleManualHistoryReceiptViewPdf(
      BuildContext context, String saleId) async {
    final sale = await _salesService.getSaleById(saleId);
    if (!context.mounted) return;
    if (sale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await ReceiptPdfService.generateSaleReceiptPdf(
        sale,
        seller: widget.seller,
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

  Future<void> _handleManualHistoryReceiptDownloadPdf(
      BuildContext context, String saleId) async {
    final sale = await _salesService.getSaleById(saleId);
    if (!context.mounted) return;
    if (sale == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await ReceiptPdfService.generateSaleReceiptPdf(
        sale,
        seller: widget.seller,
        existingDueTotal: sale.existingDueTotalAtSale,
        contextForUrduRendering: context,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final filename =
          'sale-${sale.id.substring(0, 8).toUpperCase()}.pdf';
      if (kIsWeb) {
        pdf_download.downloadPdf(bytes, filename);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF downloaded: $filename'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final xFile = XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: filename,
        );
        await Share.shareXFiles([xFile], text: 'Sale receipt');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Share sheet opened for PDF'),
              backgroundColor: Colors.green,
            ),
          );
        }
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

  void _showAddManualDuePaymentDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController referenceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDate = DateTime.now();
    final openDueFuture = _sellerService.fetchOpenDueHistoryDocs(widget.seller.id);

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        bool paySpecificInvoice = false;
        String? selectedOpenDueDocId;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              const Text('Add Manual Due Payment'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_rupee),
                      hintText: 'Enter amount',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter amount';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pay specific invoice'),
                    subtitle: Text(
                      paySpecificInvoice
                          ? 'Payment will be applied only to selected sale'
                          : 'Payment follows oldest-due-first allocation',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    value: paySpecificInvoice,
                    onChanged: (v) {
                      setDialogState(() {
                        paySpecificInvoice = v;
                        if (!v) selectedOpenDueDocId = null;
                      });
                    },
                  ),
                  if (paySpecificInvoice) ...[
                    const SizedBox(height: 8),
                    FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                      future: openDueFuture,
                      builder: (context, dueSnapshot) {
                        if (dueSnapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          );
                        }
                        final openRows = dueSnapshot.data ?? const [];
                        if (openRows.isEmpty) {
                          return Text(
                            'No open due invoices found.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          );
                        }
                        return DropdownButtonFormField<String>(
                          value: selectedOpenDueDocId,
                          decoration: const InputDecoration(
                            labelText: 'Select invoice *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.receipt_long),
                          ),
                          items: openRows.map((doc) {
                            final data = doc.data();
                            final saleId = (data['saleId'] as String?) ?? '';
                            final due = (data['duePayment'] ?? 0).toDouble();
                            final shortId = saleId.length >= 8
                                ? saleId.substring(0, 8).toUpperCase()
                                : saleId.toUpperCase();
                            return DropdownMenuItem<String>(
                              value: doc.id,
                              child: Text('Sale #$shortId  •  Due ${_currencyFormatter.format(due)}'),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setDialogState(() {
                              selectedOpenDueDocId = v;
                            });
                          },
                          validator: (v) {
                            if (paySpecificInvoice && (v == null || v.isEmpty)) {
                              return 'Please select an invoice';
                            }
                            return null;
                          },
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 365)), // Allow up to 1 year in future if needed
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? _dateFormatter.format(selectedDate!)
                            : 'Select date',
                        style: TextStyle(
                          color: selectedDate != null
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt),
                      hintText: 'Optional reference number',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                if (formKey.currentState!.validate() && selectedDate != null) {
                  setDialogState(() => isSaving = true);
                  try {
                    final amount = double.parse(amountController.text);
                    final referenceNumber = referenceController.text.trim();
                    final saleId = const Uuid().v4();
                    final paymentDate = selectedDate!;
                    final openDueRows = await openDueFuture;
                    final totalDue = openDueRows.fold<double>(
                      0.0,
                      (sum, d) => sum + (d.data()['duePayment'] ?? 0).toDouble(),
                    );

                    double remainingPayment = amount;
                    double amountAppliedToDues = 0.0;

                    if (paySpecificInvoice && selectedOpenDueDocId != null) {
                      final targetRef = FirebaseFirestore.instance
                          .collection('seller_history')
                          .doc(selectedOpenDueDocId);
                      final targetSnap = await targetRef.get();
                      if (!targetSnap.exists || targetSnap.data() == null) {
                        throw Exception('Selected invoice not found');
                      }
                      final target = targetSnap.data()!;
                      final targetSellerId = target['sellerId'] as String?;
                      if (targetSellerId != widget.seller.id) {
                        throw Exception('Selected invoice does not belong to this seller');
                      }
                      final currentDue = (target['duePayment'] ?? 0).toDouble();
                      if (currentDue <= 0) {
                        throw Exception('Selected invoice is already cleared');
                      }
                      amountAppliedToDues =
                          amount < currentDue ? amount : currentDue;
                      remainingPayment = amount - amountAppliedToDues;
                      await targetRef.update({
                        'duePayment': currentDue - amountAppliedToDues,
                        'amountPaid':
                            (target['amountPaid'] ?? 0).toDouble() + amountAppliedToDues,
                      });
                    } else {
                      // One seller_history read + batched due updates (avoids N sequential writes).
                      final applyResult = await _sellerService
                          .applyPaymentToDuePaymentsWithMetrics(
                        widget.seller.id,
                        amount,
                        prioritizeBillsWithSaleDateSameDayAs: paymentDate,
                      );
                      remainingPayment = applyResult.remainingPayment;
                      amountAppliedToDues = amount - remainingPayment;
                    }
                    
                    // If there's remaining payment after clearing all dues, it becomes credit
                    double creditAmount = 0.0;
                    if (remainingPayment > 0) {
                      creditAmount = remainingPayment;
                      await _sellerService.addCreditBalance(
                        widget.seller.id,
                        creditAmount,
                        description: 'Manual payment - excess amount',
                        referenceNumber: referenceNumber.isNotEmpty ? referenceNumber : null,
                      );
                    }
                    
                    // Create a sale record for the manual payment
                    // Only the amount applied to dues is recovery balance (recovering money from dues)
                    // Credit amount is pre-paid for future sales, not recovery
                    final manualSale = Sale(
                      id: saleId,
                      items: [], // No items for manual payment
                      total: 0.0, // No sale amount (this is just a payment, not a sale)
                      profit: 0.0, // No profit on manual payments
                      amountPaid: amount,
                      change: 0.0,
                      createdAt: paymentDate,
                      customerName: 'Manual Payment - ${widget.seller.name}',
                      paymentMethod: 'cash',
                      returnedAmount: 0.0,
                      isPartialReturn: false,
                      sellerId: widget.seller.id,
                      recoveryBalance: amountAppliedToDues, // Only amount applied to dues is recovery
                      existingDueTotalAtSale: totalDue,
                    );
                    
                    // Save the sale to increase recovery balance (only for dues portion)
                    await _salesService.addSale(manualSale);
                    
                    // Create a manual due payment record in seller_history
                    // recordType: 'payment' = due payment (user paid money); distinct from manual sale
                    await FirebaseFirestore.instance
                        .collection('seller_history')
                        .add({
                      'sellerId': widget.seller.id,
                      'saleId': saleId,
                      'saleAmount': amountAppliedToDues > 0 ? amountAppliedToDues : 0.0,
                      'amountPaid': amountAppliedToDues, // Only amount applied to dues
                      'duePayment': 0.0, // No remaining due since it's a payment
                      'saleDate': paymentDate.toIso8601String(),
                      'createdAt': DateTime.now().toIso8601String(),
                      'referenceNumber': referenceNumber.isNotEmpty
                          ? referenceNumber
                          : null,
                      'isManual': true,
                      'recordType': 'payment', // Due payment received (not a sale)
                    });

                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      final remainingDueAfter =
                          (totalDue - amountAppliedToDues).clamp(0.0, double.infinity);
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Manual payment saved'),
                          content: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Amount paid: ${_currencyFormatter.format(amount)}',
                                ),
                                if (amountAppliedToDues > 0.001)
                                  Text(
                                    'Applied to dues: ${_currencyFormatter.format(amountAppliedToDues)}',
                                  ),
                                if (paySpecificInvoice)
                                  const Text(
                                    'Mode: Specific invoice payment',
                                  ),
                                if (creditAmount > 0.001)
                                  Text(
                                    'Added to credit: ${_currencyFormatter.format(creditAmount)}',
                                  ),
                                if (totalDue > 0.001)
                                  Text(
                                    'Due before: ${_currencyFormatter.format(totalDue)}',
                                  ),
                                Text(
                                  'Due after: ${_currencyFormatter.format(remainingDueAfter)}',
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                            FilledButton.icon(
                              icon: const Icon(Icons.print),
                              label: const Text('Print receipt'),
                              onPressed: () async {
                                await _printThermalReceiptForSeller(ctx, manualSale);
                              },
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error adding payment: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (dialogContext.mounted) {
                      setDialogState(() => isSaving = false);
                    }
                  }
                } else if (selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a date'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('Saving...'),
                      ],
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.save, size: 20),
                        SizedBox(width: 8),
                        Text('Save'),
                      ],
                    ),
            ),
          ],
        ),
      );
      },
    );
  }

  void _showAddManualSaleDialog(BuildContext context) {
    final TextEditingController saleAmountController = TextEditingController();
    final TextEditingController amountPaidController = TextEditingController();
    final TextEditingController referenceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.add_shopping_cart, color: Colors.green.shade700),
              const SizedBox(width: 12),
              const Text('Add Manual Sale'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: saleAmountController,
                    decoration: const InputDecoration(
                      labelText: 'Sale Amount *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_rupee),
                      hintText: 'Enter sale amount',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter sale amount';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountPaidController,
                    decoration: const InputDecoration(
                      labelText: 'Amount Paid *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payment),
                      hintText: 'Enter amount paid',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter amount paid';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount < 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Sale Date *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? _dateFormatter.format(selectedDate!)
                            : 'Select date',
                        style: TextStyle(
                          color: selectedDate != null
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt),
                      hintText: 'Optional reference number',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                if (formKey.currentState!.validate() && selectedDate != null) {
                  final saleAmount = double.parse(saleAmountController.text);
                  final amountPaid = double.parse(amountPaidController.text);
                  if (amountPaid > saleAmount) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Amount paid cannot exceed sale amount'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  setDialogState(() => isSaving = true);
                  try {
                    final referenceNumber = referenceController.text.trim();
                    final saleId = const Uuid().v4();
                    final saleDate = selectedDate!;
                    final existingDueBeforeSale = await _sellerService
                        .getTotalDueAmountForSeller(widget.seller.id);
                    
                    // Calculate profit (0 for manual sales, or you can add a profit field)
                    final profit = 0.0;
                    
                    // Create a sale record for the manual sale
                    final manualSale = Sale(
                      id: saleId,
                      items: [], // No items for manual sale
                      total: saleAmount,
                      profit: profit,
                      amountPaid: amountPaid,
                      change: 0.0,
                      createdAt: saleDate,
                      customerName: 'Manual Sale - ${widget.seller.name}',
                      paymentMethod: 'cash',
                      returnedAmount: 0.0,
                      isPartialReturn: false,
                      sellerId: widget.seller.id,
                      recoveryBalance: 0.0, // No recovery balance for new sales
                      existingDueTotalAtSale: existingDueBeforeSale,
                    );
                    
                    // Save the sale
                    await _salesService.addSale(manualSale);
                    
                    await _sellerService.addSellerHistory(
                      sellerId: widget.seller.id,
                      saleId: saleId,
                      saleAmount: saleAmount,
                      amountPaid: amountPaid,
                      saleDate: saleDate,
                      referenceNumber:
                          referenceNumber.isNotEmpty ? referenceNumber : null,
                      isManual: true,
                    );

                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      final dueOnThisSale =
                          (saleAmount - amountPaid).clamp(0.0, double.infinity);
                      final totalDueAfter = existingDueBeforeSale +
                          saleAmount -
                          amountPaid;
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Manual sale saved'),
                          content: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Sale amount: ${_currencyFormatter.format(saleAmount)}',
                                ),
                                Text(
                                  'Amount paid: ${_currencyFormatter.format(amountPaid)}',
                                ),
                                if (dueOnThisSale > 0.001)
                                  Text(
                                    'Due on this sale: ${_currencyFormatter.format(dueOnThisSale)}',
                                  ),
                                if (existingDueBeforeSale > 0.001)
                                  Text(
                                    'Previous due: ${_currencyFormatter.format(existingDueBeforeSale)}',
                                  ),
                                Text(
                                  'Total due after: ${_currencyFormatter.format(totalDueAfter)}',
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                            FilledButton.icon(
                              icon: const Icon(Icons.print),
                              label: const Text('Print receipt'),
                              onPressed: () async {
                                await _printThermalReceiptForSeller(ctx, manualSale);
                              },
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error adding sale: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (dialogContext.mounted) {
                      setDialogState(() => isSaving = false);
                    }
                  }
                } else if (selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a date'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text('Saving...'),
                      ],
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.save, size: 20),
                        SizedBox(width: 8),
                        Text('Save'),
                      ],
                    ),
            ),
          ],
        ),
      );
      },
    );
  }

  void _showEditManualSaleDialog(
    BuildContext context, {
    required String saleId,
    required double saleAmount,
    required double amountPaid,
    required DateTime? saleDate,
    String? referenceNumber,
  }) {
    final TextEditingController saleAmountController = TextEditingController(text: saleAmount.toString());
    final TextEditingController amountPaidController = TextEditingController(text: amountPaid.toString());
    final TextEditingController referenceController = TextEditingController(text: referenceNumber ?? '');
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDate = saleDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              const Text('Edit Manual Sale'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: saleAmountController,
                    decoration: const InputDecoration(
                      labelText: 'Sale Amount *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_rupee),
                      hintText: 'Enter sale amount',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter sale amount';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountPaidController,
                    decoration: const InputDecoration(
                      labelText: 'Amount Paid *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payment),
                      hintText: 'Enter amount paid',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter amount paid';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount < 0) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Sale Date *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? _dateFormatter.format(selectedDate!)
                            : 'Select date',
                        style: TextStyle(
                          color: selectedDate != null
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt),
                      hintText: 'Optional reference number',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate() && selectedDate != null) {
                  try {
                    final newSaleAmount = double.parse(saleAmountController.text);
                    final newAmountPaid = double.parse(amountPaidController.text);
                    final newReferenceNumber = referenceController.text.trim();
                    final newSaleDate = selectedDate!;
                    
                    // Validate that amount paid doesn't exceed sale amount
                    if (newAmountPaid > newSaleAmount) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Amount paid cannot exceed sale amount'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    
                    // Calculate new due payment
                    final newDuePayment = newSaleAmount > newAmountPaid ? newSaleAmount - newAmountPaid : 0.0;
                    
                    // Update the sale record
                    await FirebaseFirestore.instance
                        .collection('sales')
                        .doc(saleId)
                        .update({
                      'total': newSaleAmount,
                      'amountPaid': newAmountPaid,
                      'createdAt': newSaleDate.toIso8601String(),
                      'customerName': 'Manual Sale - ${widget.seller.name}',
                    });
                    
                    // Update seller_history record
                    final sellerHistorySnapshot = await FirebaseFirestore.instance
                        .collection('seller_history')
                        .where('saleId', isEqualTo: saleId)
                        .get();
                    
                    if (sellerHistorySnapshot.docs.isNotEmpty) {
                      await sellerHistorySnapshot.docs.first.reference.update({
                        'saleAmount': newSaleAmount,
                        'amountPaid': newAmountPaid,
                        'duePayment': newDuePayment,
                        'saleDate': newSaleDate.toIso8601String(),
                        'referenceNumber': newReferenceNumber.isNotEmpty
                            ? newReferenceNumber
                            : null,
                        'isManual': true,
                      });
                    }

                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Manual sale updated successfully.',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating sale: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } else if (selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a date'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Update'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReduceCreditBalanceDialog(BuildContext context, double currentCreditBalance) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.remove_circle, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              const Text('Reduce Credit Balance'),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Current Credit: ${_currencyFormatter.format(currentCreditBalance)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount to Reduce *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.currency_rupee),
                      helperText: 'Max: ${_currencyFormatter.format(currentCreditBalance)}',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter amount';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Please enter a valid amount';
                      }
                      if (amount > currentCreditBalance) {
                        return 'Amount cannot exceed credit balance';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Payment Date *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        selectedDate != null
                            ? _dateFormatter.format(selectedDate!)
                            : 'Select date',
                        style: TextStyle(
                          color: selectedDate != null
                              ? Colors.black
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                      hintText: 'Optional description',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Reference Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt),
                      hintText: 'Optional reference number',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate() && selectedDate != null) {
                  try {
                    final amount = double.parse(amountController.text);
                    final referenceNumber = referenceController.text.trim();
                    final description = descriptionController.text.trim();
                    
                    await _sellerService.reduceCreditBalance(
                      widget.seller.id,
                      amount,
                      description: description.isNotEmpty ? description : null,
                      referenceNumber: referenceNumber.isNotEmpty ? referenceNumber : null,
                    );
                    
                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Credit balance reduced by ${_currencyFormatter.format(amount)} successfully',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error reducing credit balance: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } else if (selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a date'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Reduce Credit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCreditBalanceDialog(BuildContext context, double currentCreditBalance) {
    final formKey = GlobalKey<FormState>();
    final creditController = TextEditingController(
      text: currentCreditBalance.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Credit Balance'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: creditController,
                decoration: const InputDecoration(
                  labelText: 'Credit Balance',
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter credit balance';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null) {
                    return 'Please enter a valid number';
                  }
                  if (amount < 0) {
                    return 'Credit balance cannot be negative';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final newCreditBalance = double.parse(creditController.text);
                  await _sellerService.updateCreditBalance(
                    widget.seller.id,
                    newCreditBalance,
                  );
                  
                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    // Force rebuild to refresh credit balance display
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Credit balance updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating credit balance: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCreditBalanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Credit Balance and History'),
        content: const Text(
          'This will delete all credit balance and seller history records. '
          'This action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _sellerService.deleteCreditBalanceWithHistory(widget.seller.id);
                
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  // Force rebuild to refresh display (seller_history StreamBuilder will auto-update)
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Credit balance and history deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting credit balance and history: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteManualSaleDialog(
    BuildContext context,
    String saleId,
    double saleAmount,
    double duePayment,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Manual Sale'),
        content: Text(
          'Are you sure you want to delete this manual sale?\n\n'
          'Sale Amount: ${_currencyFormatter.format(saleAmount)}\n'
          'Due Payment: ${_currencyFormatter.format(duePayment)}\n\n'
          'This will delete the sale record and seller history. '
          'Unpaid sales on the dashboard will be reduced. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // Delete the sale record
                await _salesService.deleteSale(saleId);
                
                // Delete the seller_history record
                final sellerHistorySnapshot = await FirebaseFirestore.instance
                    .collection('seller_history')
                    .where('saleId', isEqualTo: saleId)
                    .get();
                
                for (var doc in sellerHistorySnapshot.docs) {
                  await doc.reference.delete();
                }
                
                // Delete due payment if exists
                final duePaymentSnapshot = await FirebaseFirestore.instance
                    .collection('due_payments')
                    .where('saleId', isEqualTo: saleId)
                    .get();
                
                for (var doc in duePaymentSnapshot.docs) {
                  await doc.reference.delete();
                }
                
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  setState(() {}); // Force rebuild to refresh display
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Manual sale deleted successfully. Unpaid sales updated.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting manual sale: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

