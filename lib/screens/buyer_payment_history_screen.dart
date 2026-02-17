import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../models/buyer.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_payment.dart';
import '../services/buyer_bill_service.dart';
import '../services/buyer_payment_service.dart';
import '../utils/pdf_download_stub.dart' if (dart.library.html) '../utils/pdf_download_web.dart' as pdf_download;

class BuyerPaymentHistoryScreen extends StatefulWidget {
  final Buyer buyer;

  const BuyerPaymentHistoryScreen({super.key, required this.buyer});

  @override
  State<BuyerPaymentHistoryScreen> createState() => _BuyerPaymentHistoryScreenState();
}

class _BuyerPaymentHistoryScreenState extends State<BuyerPaymentHistoryScreen> {
  final BuyerBillService _billService = BuyerBillService();
  final BuyerPaymentService _paymentService = BuyerPaymentService();
  DateTime? _startDate;
  DateTime? _endDate;
  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');
  final DateFormat _dateTimeFormatter = DateFormat('MMM dd, yyyy - hh:mm a');
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.buyer.name} - Payment History'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Date Filter
          _buildDateFilter(),
          
          // Payment History List
          Expanded(
            child: _buildPaymentHistory(),
          ),
        ],
      ),
    );
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
      final paymentsData = await _fetchFilteredPayments();
      final bills = await _billService.getBillsByBuyer(widget.buyer.id).first;
      final allPaymentsData = await _getAllPaymentsWithBills(bills);
      final totalBills = bills.fold<double>(0.0, (sum, b) => sum + b.finalPrice);
      final totalPaidAll = allPaymentsData.fold<double>(0.0, (sum, p) => sum + (p['payment'] as BuyerPayment).amount);
      final totalDue = (totalBills - totalPaidAll).clamp(0.0, double.infinity);
      final pdfBytes = await _generatePaymentHistoryPdf(paymentsData, totalDue: totalDue);

      if (!context.mounted) return;
      setState(() => _isGeneratingPdf = false);

      await _showPdfOptionsDialog(context, pdfBytes);
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

  Future<List<Map<String, dynamic>>> _fetchFilteredPayments() async {
    final bills = await _billService.getBillsByBuyer(widget.buyer.id).first;
    final allPayments = await _getAllPaymentsWithBills(bills);

    if (_startDate == null || _endDate == null) return allPayments;

    return allPayments.where((paymentData) {
      final payment = paymentData['payment'] as BuyerPayment;
      final paymentDate = DateTime(
        payment.paymentDate.year,
        payment.paymentDate.month,
        payment.paymentDate.day,
      );
      final startOnly = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      final endOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
      return !paymentDate.isBefore(startOnly) && !paymentDate.isAfter(endOnly);
    }).toList()
      ..sort((a, b) {
        final aP = a['payment'] as BuyerPayment;
        final bP = b['payment'] as BuyerPayment;
        return aP.paymentDate.compareTo(bP.paymentDate); // Oldest first for PDF
      });
  }

  Future<Uint8List> _generatePaymentHistoryPdf(List<Map<String, dynamic>> paymentsData, {double totalDue = 0}) async {
    final pdf = pw.Document();
    final dateRangeStr = '${_dateFormatter.format(_startDate!)} - ${_dateFormatter.format(_endDate!)}';

    final totalPaid = paymentsData.fold<double>(
      0.0,
      (sum, p) => sum + (p['payment'] as BuyerPayment).amount,
    );

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
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
            child: pw.Text('Bill', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Bank / Ref', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    ];

    for (final pd in paymentsData) {
      final payment = pd['payment'] as BuyerPayment;
      final bill = pd['bill'] as BuyerBill?;
      final isCash = payment.paymentType == 'cash';
      final billDisplay = bill != null ? (bill.billNumber ?? 'BILL-${bill.id.length >= 8 ? bill.id.substring(0, 8).toUpperCase() : bill.id.toUpperCase()}') : '-';
      final bankInfo = payment.paymentType == 'bank_transfer'
          ? [
              if (payment.accountTitle != null) payment.accountTitle!,
              if (payment.bankName != null) payment.bankName!,
              if (payment.referenceNumber != null) 'Ref: ${payment.referenceNumber}',
            ].join(', ')
          : '-';
      final paymentIdDisplay = payment.paymentNumber ?? '-';

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isCash ? PdfColors.green50 : PdfColors.blue50,
          ),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(paymentIdDisplay, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(_dateTimeFormatter.format(payment.paymentDate), style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                isCash ? 'Cash' : 'Bank Transfer',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: isCash ? PdfColors.green800 : PdfColors.blue800,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(billDisplay, style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                _currencyFormatter.format(payment.amount),
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(bankInfo, style: const pw.TextStyle(fontSize: 8)),
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
                pw.Text('Payment History Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(widget.buyer.name, style: const pw.TextStyle(fontSize: 14)),
                pw.Text('Date Range: $dateRangeStr', style: const pw.TextStyle(fontSize: 10)),
                if (widget.buyer.phone != null && widget.buyer.phone!.trim().isNotEmpty)
                  pw.Text('Phone: ${widget.buyer.phone}', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'All payments in chronological order.',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Payments', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text('${paymentsData.length}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Paid (Period)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(_currencyFormatter.format(totalPaid), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Due Payment', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.Text(_currencyFormatter.format(totalDue), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: totalDue > 0 ? PdfColors.orange800 : PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(2),
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

  Future<void> _showPdfOptionsDialog(BuildContext context, Uint8List pdfBytes) async {
    final filename = 'payment_history_${widget.buyer.name.replaceAll(' ', '_')}_${_dateFormatter.format(_startDate!)}_${_dateFormatter.format(_endDate!)}.pdf'
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
        content: const Text(
          'Payment history PDF has been generated. View or download it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
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
                await Share.shareXFiles([xFile], text: 'Payment History Report - ${widget.buyer.name}');
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

  Widget _buildPaymentHistory() {
    return StreamBuilder<List<BuyerBill>>(
      stream: _billService.getBillsByBuyer(widget.buyer.id),
      builder: (context, billsSnapshot) {
        if (!billsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final bills = billsSnapshot.data ?? [];
        
        // Get all payments for all bills
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _getAllPaymentsWithBills(bills),
          builder: (context, paymentsSnapshot) {
            if (!paymentsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var allPayments = paymentsSnapshot.data!;
            // Due Payment = total bills - actual payments (matches Bills screen)
            final totalBills = bills.fold<double>(0.0, (sum, b) => sum + b.finalPrice);
            final totalPaidAll = allPayments.fold<double>(0.0, (sum, p) => sum + (p['payment'] as BuyerPayment).amount);
            final totalDue = (totalBills - totalPaidAll).clamp(0.0, double.infinity);

            // Apply date filter
            if (_startDate != null || _endDate != null) {
              allPayments = allPayments.where((paymentData) {
                final payment = paymentData['payment'] as BuyerPayment;
                final paymentDate = DateTime(
                  payment.paymentDate.year,
                  payment.paymentDate.month,
                  payment.paymentDate.day,
                );
                
                if (_startDate != null) {
                  final startDateOnly = DateTime(
                    _startDate!.year,
                    _startDate!.month,
                    _startDate!.day,
                  );
                  if (paymentDate.isBefore(startDateOnly)) return false;
                }
                
                if (_endDate != null) {
                  final endDateOnly = DateTime(
                    _endDate!.year,
                    _endDate!.month,
                    _endDate!.day,
                  );
                  if (paymentDate.isAfter(endDateOnly)) return false;
                }
                
                return true;
              }).toList();
            }

            // Sort by date descending
            allPayments.sort((a, b) {
              final aPayment = a['payment'] as BuyerPayment;
              final bPayment = b['payment'] as BuyerPayment;
              return bPayment.paymentDate.compareTo(aPayment.paymentDate);
            });

            if (allPayments.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payment, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'No payment history found',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _startDate != null || _endDate != null
                          ? 'Try adjusting your date filter'
                          : 'No payments recorded yet',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            // Total paid in filtered period
            final totalPaid = allPayments.fold<double>(
              0.0,
              (sum, p) => sum + (p['payment'] as BuyerPayment).amount,
            );

            return Column(
              children: [
                // Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Payments',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${allPayments.length}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Paid',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currencyFormatter.format(totalPaid),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Due Payment',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currencyFormatter.format(totalDue),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: totalDue > 0 ? Colors.orange.shade700 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Payments List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: allPayments.length,
                    itemBuilder: (context, index) {
                      final paymentData = allPayments[index];
                      final payment = paymentData['payment'] as BuyerPayment;
                      final bill = paymentData['bill'] as BuyerBill?;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: payment.paymentType == 'cash'
                                ? Colors.green.shade100
                                : Colors.blue.shade100,
                            child: Icon(
                              payment.paymentType == 'cash' ? Icons.money : Icons.account_balance,
                              color: payment.paymentType == 'cash'
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _currencyFormatter.format(payment.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: payment.paymentType == 'cash'
                                      ? Colors.green.shade50
                                      : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  payment.paymentType == 'cash' ? 'Cash' : 'Bank Transfer',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: payment.paymentType == 'cash'
                                        ? Colors.green.shade700
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (payment.paymentNumber != null)
                                Text(
                                  'ID: ${payment.paymentNumber}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              if (payment.paymentNumber != null) const SizedBox(height: 4),
                              if (bill != null)
                                Text(
                                  'Bill: ${bill.billNumber ?? 'Bill #${bill.id.substring(0, 8).toUpperCase()}'}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              Text(
                                _dateTimeFormatter.format(payment.paymentDate),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (payment.paymentType == 'bank_transfer') ...[
                                const SizedBox(height: 4),
                                if (payment.accountTitle != null)
                                  Text('Account: ${payment.accountTitle}'),
                                if (payment.bankName != null)
                                  Text('Bank: ${payment.bankName}'),
                                if (payment.accountHolderName != null)
                                  Text('Holder: ${payment.accountHolderName}'),
                                if (payment.referenceNumber != null)
                                  Text('Ref: ${payment.referenceNumber}'),
                              ],
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deletePayment(context, payment),
                            tooltip: 'Delete Payment',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getAllPaymentsWithBills(List<BuyerBill> bills) async {
    final List<Map<String, dynamic>> allPayments = [];
    
    for (var bill in bills) {
      final payments = await _paymentService.getPaymentsByBill(bill.id).first;
      for (var payment in payments) {
        allPayments.add({
          'payment': payment,
          'bill': bill,
        });
      }
    }
    
    return allPayments;
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

  void _deletePayment(BuildContext context, BuyerPayment payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Payment'),
        content: Text('Are you sure you want to delete this payment of ${_currencyFormatter.format(payment.amount)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _paymentService.deletePayment(payment.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Payment deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
