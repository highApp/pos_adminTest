import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/buyer.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_payment.dart';
import '../services/buyer_bill_service.dart';
import '../services/buyer_payment_service.dart';

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

            // Calculate totals
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Payments: ${allPayments.length}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currencyFormatter.format(totalPaid),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
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
