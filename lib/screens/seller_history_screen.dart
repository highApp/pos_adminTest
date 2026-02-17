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
import '../utils/pdf_download_stub.dart' if (dart.library.html) '../utils/pdf_download_web.dart' as pdf_download;

class SellerHistoryScreen extends StatefulWidget {
  final Seller seller;

  const SellerHistoryScreen({super.key, required this.seller});

  @override
  State<SellerHistoryScreen> createState() => _SellerHistoryScreenState();
}

class _SellerHistoryScreenState extends State<SellerHistoryScreen> with SingleTickerProviderStateMixin {
  final SellerService _sellerService = SellerService();
  final SalesService _salesService = SalesService();
  DateTime? _startDate;
  DateTime? _endDate;
  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');
  final DateFormat _dateTimeFormatter = DateFormat('MMM dd, yyyy - hh:mm a');
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
            icon: const Icon(Icons.add_shopping_cart),
            tooltip: 'Add Manual Sale',
            onPressed: () => _showAddManualSaleDialog(context),
          ),
        ],
      ),
      body: Column(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddManualSaleDialog(context),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Add Manual Sale'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSummaryCards() {
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
                                        'Due Payment',
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
                                        'Total Sale',
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
        
        // Calculate total sale by fetching actual sale data to account for returns
        // This ensures we use netTotal (total - returnedAmount) instead of relying on seller_history.saleAmount
        return FutureBuilder<List<double>>(
          future: Future.wait([
            _calculateTotalSaleFromActualSales(allRecords),
            _sellerService.getCreditBalance(widget.seller.id),
          ]),
          builder: (context, saleSnapshot) {
            final totalSale = saleSnapshot.data?[0] ?? 0.0;
            final creditBalance = saleSnapshot.data?[1] ?? 0.0;
            
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
                                      Text(
                                        'Due Payment',
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
                                    _currencyFormatter.format(totalDue),
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
                                      'Total Sale',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.green.shade900,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                saleSnapshot.connectionState == ConnectionState.waiting
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : SelectableText(
                                        _currencyFormatter.format(totalSale),
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

    // Resolve record types for existing data: isManual=true can be Sale (manual sale) or Payment (manual due payment)
    final resolvedTypes = <int, bool>{}; // index -> isPayment (true = payment, false = sale)
    for (int i = 0; i < history.length; i++) {
      final record = history[i];
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

      resolvedTypes[i] = isPayment;
    }

    double totalSalesAmount = 0;
    double totalPaymentsReceived = 0;
    double totalDueOutstanding = 0;

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Type', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Sale ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Sale Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Paid', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Due', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Ref', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    ];

    for (int i = 0; i < history.length; i++) {
      final record = history[i];
      final saleAmount = (record['saleAmount'] ?? 0).toDouble();
      final amountPaid = (record['amountPaid'] ?? 0).toDouble();
      final duePayment = (record['duePayment'] ?? 0).toDouble();
      final saleId = record['saleId'] ?? '';
      final saleDateStr = record['saleDate'];
      final saleDate = saleDateStr != null ? DateTime.parse(saleDateStr) : null;
      final referenceNumber = record['referenceNumber'] as String?;
      final isPaymentRecord = resolvedTypes[i] ?? false;

      if (isPaymentRecord) {
        // Manual payment (money received to reduce dues)
        totalPaymentsReceived += saleAmount;
        tableRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.green50),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(saleDate != null ? _dateTimeFormatter.format(saleDate) : '-', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Payment', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('-', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('-', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(_currencyFormatter.format(saleAmount), style: pw.TextStyle(fontSize: 9, color: PdfColors.green800)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Applied to dues', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(referenceNumber ?? '-', style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
          ),
        );
      } else {
        // SALE record
        totalSalesAmount += saleAmount;
        totalDueOutstanding += duePayment;
        tableRows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(saleDate != null ? _dateTimeFormatter.format(saleDate) : '-', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text('Sale', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(saleId.length >= 8 ? saleId.substring(0, 8).toUpperCase() : saleId, style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(_currencyFormatter.format(saleAmount), style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(_currencyFormatter.format(amountPaid), style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(_currencyFormatter.format(duePayment), style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(referenceNumber ?? '-', style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
          ),
        );
      }
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
                pw.Text('Seller History Report (Date-wise)', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(widget.seller.name, style: const pw.TextStyle(fontSize: 14)),
                pw.Text('Date Range: $dateRangeStr', style: const pw.TextStyle(fontSize: 10)),
                if (widget.seller.phone != null && widget.seller.phone!.isNotEmpty)
                  pw.Text('Phone: ${widget.seller.phone}', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Sales and payments in chronological order. "Payment" = manual payment received (reduces due).',
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
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
              6: const pw.FlexColumnWidth(1),
            },
            children: tableRows,
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Summary (Filtered Period)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.Text('Total Sales: ${_currencyFormatter.format(totalSalesAmount)}', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Total Payments Received: ${_currencyFormatter.format(totalPaymentsReceived)}', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Outstanding Due: ${_currencyFormatter.format(totalDueOutstanding)}', style: const pw.TextStyle(fontSize: 11)),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Note: Sales show current Paid/Due. Payments are separate entries when you add manual payment.',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
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
          itemCount: history.length,
          itemBuilder: (context, index) {
            final record = history[index];
            final saleAmount = (record['saleAmount'] ?? 0).toDouble();
            final amountPaid = (record['amountPaid'] ?? 0).toDouble();
            final duePayment = (record['duePayment'] ?? 0).toDouble();
            final saleDate = record['saleDate'] != null
                ? DateTime.parse(record['saleDate'])
                : null;
            final saleId = record['saleId'] ?? '';
            final referenceNumber = record['referenceNumber'] as String?;
            final isManual = record['isManual'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: duePayment > 0
                      ? Colors.orange.shade100
                      : Colors.green.shade100,
                  child: Icon(
                    duePayment > 0 ? Icons.pending : Icons.check_circle,
                    color: duePayment > 0
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
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
                            'Sale #${saleId.substring(0, 8).toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isManual)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
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
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
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
                            SelectableText(
                              'Sale Amount: ${_currencyFormatter.format(saleAmount)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            SelectableText(
                              'Amount Paid: ${_currencyFormatter.format(amountPaid)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
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
                        if (duePayment > 0)
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
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200!),
                            ),
                            child: Text(
                              'Paid',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap to view order details',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
                children: [
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
                                        SelectableText(
                                          'Profit: ${_currencyFormatter.format(sale.profit)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
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
                              
                              const SizedBox(height: 8),
                              
                              // Net Profit
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
          },
        );
      },
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
    return FirebaseFirestore.instance
        .collection('seller_history')
        .where('sellerId', isEqualTo: widget.seller.id)
        .snapshots()
        .map((snapshot) {
      var records = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          ...data,
          'id': doc.id,
        };
      }).toList();

      // Apply date filter
      if (_startDate != null || _endDate != null) {
        records = records.where((record) {
          final saleDateStr = record['saleDate'];
          if (saleDateStr == null) return false;
          
          final saleDate = DateTime.parse(saleDateStr);
          final saleDateOnly = DateTime(saleDate.year, saleDate.month, saleDate.day);
          
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

      // Sort by date descending (newest first)
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
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('seller_history')
                      .where('sellerId', isEqualTo: widget.seller.id)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    // Filter and sort in memory to avoid composite index requirement
                    final allDocs = snapshot.data?.docs ?? [];
                    final duePayments = allDocs
                        .where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final duePayment = (data['duePayment'] ?? 0).toDouble();
                          return duePayment > 0;
                        })
                        .toList()
                      ..sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final aDate = aData['createdAt'] != null
                            ? DateTime.parse(aData['createdAt'])
                            : DateTime(1970);
                        final bDate = bData['createdAt'] != null
                            ? DateTime.parse(bData['createdAt'])
                            : DateTime(1970);
                        return bDate.compareTo(aDate); // Descending
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

  void _showAddManualDuePaymentDialog(BuildContext context) {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController referenceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate() && selectedDate != null) {
                  try {
                    final amount = double.parse(amountController.text);
                    final referenceNumber = referenceController.text.trim();
                    final saleId = const Uuid().v4();
                    final paymentDate = selectedDate!;
                    
                    // Get total due amount first
                    final totalDue = await _sellerService.getTotalDueAmountForSeller(widget.seller.id);
                    
                    // Apply payment to existing due payments first
                    final remainingPayment = await _sellerService.applyPaymentToDuePayments(
                      widget.seller.id,
                      amount,
                    );
                    
                    // Calculate how much was applied to dues
                    final amountAppliedToDues = amount - remainingPayment;
                    
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
                    );
                    
                    // Save the sale to increase recovery balance (only for dues portion)
                    await _salesService.addSale(manualSale);
                    
                    // Create a manual due payment record in seller_history
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
                    });

                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      String message = 'Manual payment of ${_currencyFormatter.format(amount)} added successfully.';
                      if (amountAppliedToDues > 0) {
                        message += ' Applied ${_currencyFormatter.format(amountAppliedToDues)} to due payments.';
                      }
                      if (creditAmount > 0) {
                        message += ' Credit balance: ${_currencyFormatter.format(creditAmount)}.';
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message),
                          backgroundColor: Colors.green,
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
              label: const Text('Save'),
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

  void _showAddManualSaleDialog(BuildContext context) {
    final TextEditingController saleAmountController = TextEditingController();
    final TextEditingController amountPaidController = TextEditingController();
    final TextEditingController referenceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate() && selectedDate != null) {
                  try {
                    final saleAmount = double.parse(saleAmountController.text);
                    final amountPaid = double.parse(amountPaidController.text);
                    final referenceNumber = referenceController.text.trim();
                    final saleId = const Uuid().v4();
                    final saleDate = selectedDate!;
                    
                    // Validate that amount paid doesn't exceed sale amount
                    if (amountPaid > saleAmount) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Amount paid cannot exceed sale amount'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    
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
                    );
                    
                    // Save the sale
                    await _salesService.addSale(manualSale);
                    
                    // Add seller history record
                    await _sellerService.addSellerHistory(
                      sellerId: widget.seller.id,
                      saleId: saleId,
                      saleAmount: saleAmount,
                      amountPaid: amountPaid,
                      saleDate: saleDate,
                    );
                    
                    // Add reference number if provided
                    if (referenceNumber.isNotEmpty) {
                      // Update seller_history with reference number
                      final sellerHistorySnapshot = await FirebaseFirestore.instance
                          .collection('seller_history')
                          .where('saleId', isEqualTo: saleId)
                          .get();
                      
                      if (sellerHistorySnapshot.docs.isNotEmpty) {
                        await sellerHistorySnapshot.docs.first.reference.update({
                          'referenceNumber': referenceNumber,
                          'isManual': true,
                        });
                      }
                    } else {
                      // Mark as manual even without reference
                      final sellerHistorySnapshot = await FirebaseFirestore.instance
                          .collection('seller_history')
                          .where('saleId', isEqualTo: saleId)
                          .get();
                      
                      if (sellerHistorySnapshot.docs.isNotEmpty) {
                        await sellerHistorySnapshot.docs.first.reference.update({
                          'isManual': true,
                        });
                      }
                    }

                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Manual sale of ${_currencyFormatter.format(saleAmount)} added successfully.',
                          ),
                          backgroundColor: Colors.green,
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
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
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

