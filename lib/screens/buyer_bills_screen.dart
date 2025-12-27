import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_bill_item.dart';
import '../models/buyer_payment.dart';
import '../services/buyer_bill_service.dart';
import '../services/buyer_payment_service.dart';
import 'create_edit_buyer_bill_screen.dart';
import 'add_payment_dialog.dart';
import 'buyer_payment_history_screen.dart';
import 'manual_payment_dialog.dart';

class BuyerBillsScreen extends StatefulWidget {
  final Buyer buyer;

  const BuyerBillsScreen({super.key, required this.buyer});

  @override
  State<BuyerBillsScreen> createState() => _BuyerBillsScreenState();
}

class _BuyerBillsScreenState extends State<BuyerBillsScreen> {
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
        title: Text('${widget.buyer.name} - Bills'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Total Sum Display
          _buildTotalSum(),
          
          // Payment Section
          _buildPaymentSection(),
          
          // Date Filter
          _buildDateFilter(),
          
          // Bills List
          Expanded(
            child: _buildBillsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateEditBuyerBillScreen(
                buyer: widget.buyer,
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Bill'),
        backgroundColor: Colors.purple,
      ),
    );
  }

  Widget _buildTotalSum() {
    return StreamBuilder<List<BuyerBill>>(
      stream: _getBillsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple.shade50,
            child: const Row(
              children: [
                CircularProgressIndicator(),
              ],
            ),
          );
        }

        final bills = snapshot.data ?? [];
        
        // Calculate totals with real-time payment updates
        double totalBills = bills.fold<double>(0.0, (sum, bill) => sum + bill.finalPrice);
        
        return StreamBuilder<List<BuyerPayment>>(
          stream: _getAllPaymentsStream(bills),
          builder: (context, paymentsSnapshot) {
            double totalPaid = 0.0;
            
            if (paymentsSnapshot.hasData) {
              final allPayments = paymentsSnapshot.data!;
              totalPaid = allPayments.fold<double>(0.0, (sum, payment) => sum + payment.amount);
            }
            
            final balanceDue = totalBills - totalPaid;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.purple.shade50,
              child: Row(
                children: [
                  Icon(
                    Icons.calculate,
                    color: Colors.purple.shade700,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Total Bills: ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _currencyFormatter.format(totalBills),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Total Paid: ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _currencyFormatter.format(totalPaid),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Balance Due: ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _currencyFormatter.format(balanceDue),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${bills.length} ${bills.length == 1 ? 'Bill' : 'Bills'}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
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

  Future<Map<String, double>> _calculateTotals(List<BuyerBill> bills) async {
    double totalBills = 0.0;
    double totalPaid = 0.0;

    for (var bill in bills) {
      totalBills += bill.finalPrice;
      final paid = await _paymentService.getTotalPaidForBill(bill.id);
      totalPaid += paid;
    }

    return {
      'totalBills': totalBills,
      'totalPaid': totalPaid,
    };
  }

  Stream<List<BuyerPayment>> _getAllPaymentsStream(List<BuyerBill> bills) {
    if (bills.isEmpty) {
      return Stream.value([]);
    }

    // Get all bill IDs
    final billIds = bills.map((b) => b.id).toList();
    
    // Listen to all payments and filter by bill IDs
    return _paymentService.getAllPaymentsForBuyer(billIds);
  }

  Widget _buildPaymentSection() {
    return StreamBuilder<List<BuyerBill>>(
      stream: _getBillsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final bills = snapshot.data ?? [];
        if (bills.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300!),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.payment,
                color: Colors.green.shade700,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Add Payment:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<List<BuyerPayment>>(
                  stream: _getAllPaymentsStream(bills),
                  builder: (context, paymentsSnapshot) {
                    if (!paymentsSnapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final allPayments = paymentsSnapshot.data!;
                    // Calculate balances for each bill
                    final Map<String, double> paidByBill = {};
                    for (var payment in allPayments) {
                      paidByBill[payment.billId] = (paidByBill[payment.billId] ?? 0.0) + payment.amount;
                    }
                    
                    final unpaidBills = bills.where((bill) {
                      final paid = paidByBill[bill.id] ?? 0.0;
                      return (bill.finalPrice - paid) > 0;
                    }).toList();

                    if (unpaidBills.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'All bills are fully paid',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }

                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300!),
                      ),
                      child: Text(
                        '${unpaidBills.length} ${unpaidBills.length == 1 ? 'bill' : 'bills'} with balance',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.history),
                color: Colors.blue.shade700,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BuyerPaymentHistoryScreen(buyer: widget.buyer),
                    ),
                  );
                },
                tooltip: 'Payment History',
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showManualPaymentDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _getBillsWithBalanceStream(List<BuyerBill> bills) {
    if (bills.isEmpty) {
      return Stream.value([]);
    }

    // Get real-time payment data
    return _getAllPaymentsStream(bills).map((allPayments) {
      // Calculate paid amounts per bill
      final Map<String, double> paidByBill = {};
      for (var payment in allPayments) {
        paidByBill[payment.billId] = (paidByBill[payment.billId] ?? 0.0) + payment.amount;
      }
      
      // Create bills with balance
      return bills.map((bill) {
        final paid = paidByBill[bill.id] ?? 0.0;
        final balance = bill.finalPrice - paid;
        return {
          'bill': bill,
          'balance': balance,
          'paid': paid,
        };
      }).toList();
    });
  }

  Future<List<Map<String, dynamic>>> _getBillsWithBalance(List<BuyerBill> bills) async {
    final List<Map<String, dynamic>> result = [];
    
    for (var bill in bills) {
      final totalPaid = await _paymentService.getTotalPaidForBill(bill.id);
      final balance = bill.finalPrice - totalPaid;
      result.add({
        'bill': bill,
        'balance': balance,
        'paid': totalPaid,
      });
    }
    
    return result;
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

  Widget _buildBillsList() {
    return StreamBuilder<List<BuyerBill>>(
      stream: _getBillsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final bills = snapshot.data ?? [];

        if (bills.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No bills found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _startDate != null || _endDate != null
                      ? 'Try adjusting your date filter'
                      : 'Create your first bill',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bills.length,
          itemBuilder: (context, index) {
            final bill = bills[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade100,
                  child: Icon(
                    Icons.receipt,
                    color: Colors.purple.shade700,
                  ),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          bill.billNumber ?? 'Bill #${bill.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (bill.createdAt != null)
                          Text(
                            _dateTimeFormatter.format(bill.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
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
                            Text(
                              'Total: ${_currencyFormatter.format(bill.total)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              'Expense: ${_currencyFormatter.format(bill.totalExpense)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade200!),
                          ),
                          child: Text(
                            'Final: ${_currencyFormatter.format(bill.finalPrice)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
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
                    'Tap to view bill details',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateEditBuyerBillScreen(
                              buyer: widget.buyer,
                              bill: bill,
                            ),
                          ),
                        );
                      },
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteBill(context, bill),
                      tooltip: 'Delete',
                    ),
                  ],
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300!),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Final Price at Top
                        Center(
                          child: Text(
                            _currencyFormatter.format(bill.finalPrice),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Payment Info
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              radius: 20,
                              child: Icon(
                                Icons.payment,
                                color: Colors.purple.shade700,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (bill.createdAt != null)
                                    Text(
                                      _dateTimeFormatter.format(bill.createdAt),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Payment: ${bill.paymentMethod} • Paid: ${_currencyFormatter.format(bill.amountPaid)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  if (bill.change > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Change: ${_currencyFormatter.format(bill.change)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
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
                        ...bill.items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.itemName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${item.quantity} ${item.unit} × ${_currencyFormatter.format(item.price)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      if (item.expense > 0)
                                        Text(
                                          'Expense: ${_currencyFormatter.format(item.expense)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                      if (item.date != null)
                                        Text(
                                          'Date: ${_dateFormatter.format(item.date!)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
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
                        
                        // Totals
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Subtotal:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _currencyFormatter.format(bill.total),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Expense:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _currencyFormatter.format(bill.totalExpense),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Final Price:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _currencyFormatter.format(bill.finalPrice),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                          ],
                        ),
                        if (bill.notes != null && bill.notes!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            'Notes: ${bill.notes}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        
                        // Payment History Section
                        const Text(
                          'Payment History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildPaymentHistory(bill),
                      ],
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

  Widget _buildPaymentHistory(BuyerBill bill) {
    return StreamBuilder<List<BuyerPayment>>(
      stream: _paymentService.getPaymentsByBill(bill.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final payments = snapshot.data ?? [];
        final totalPaid = payments.fold<double>(0.0, (sum, p) => sum + p.amount);
        final balanceDue = bill.finalPrice - totalPaid;

        if (payments.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.payment, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                const Text(
                  'No payments yet',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  'Balance Due: ${_currencyFormatter.format(bill.finalPrice)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Paid: ${_currencyFormatter.format(totalPaid)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Balance Due: ${_currencyFormatter.format(balanceDue)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: balanceDue > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  if (balanceDue <= 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Fully Paid',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Payments List
            ...payments.map((payment) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
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
                          fontSize: 16,
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
                      Text(
                        _dateFormatter.format(payment.paymentDate),
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
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () => _deletePayment(context, payment),
                    tooltip: 'Delete Payment',
                  ),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  void _showManualPaymentDialog(BuildContext context) async {
    // Get all bills for this buyer
    final bills = await _getBillsStream().first;
    if (bills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bills found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Calculate total balance due
    double totalBalanceDue = 0.0;
    for (var bill in bills) {
      final totalPaid = await _paymentService.getTotalPaidForBill(bill.id);
      totalBalanceDue += (bill.finalPrice - totalPaid);
    }

    if (totalBalanceDue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All bills are fully paid'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ManualPaymentDialog(
        bills: bills,
        currencyFormatter: _currencyFormatter,
        paymentService: _paymentService,
        totalBalanceDue: totalBalanceDue,
      ),
    );
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

  Stream<List<BuyerBill>> _getBillsStream() {
    if (_startDate != null || _endDate != null) {
      final startDate = _startDate ?? DateTime(2000);
      final endDate = _endDate ?? DateTime.now();
      return _billService.getBillsByBuyerAndDateRange(
        widget.buyer.id,
        startDate,
        endDate,
      );
    }
    return _billService.getBillsByBuyer(widget.buyer.id);
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

  void _deleteBill(BuildContext context, BuyerBill bill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Are you sure you want to delete this bill?\n\nBill #${bill.id.substring(0, 8).toUpperCase()}\nFinal Price: ${_currencyFormatter.format(bill.finalPrice)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _billService.deleteBill(bill.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bill deleted successfully'),
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
