import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/buyer_bill.dart';
import '../services/buyer_payment_service.dart';

class BillSelectionDialog extends StatefulWidget {
  final List<BuyerBill> bills;
  final NumberFormat currencyFormatter;

  const BillSelectionDialog({
    super.key,
    required this.bills,
    required this.currencyFormatter,
  });

  @override
  State<BillSelectionDialog> createState() => _BillSelectionDialogState();
}

class _BillSelectionDialogState extends State<BillSelectionDialog> {
  final BuyerPaymentService _paymentService = BuyerPaymentService();
  Map<String, double> _balances = {};

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  Future<void> _loadBalances() async {
    final Map<String, double> balances = {};
    for (var bill in widget.bills) {
      final totalPaid = await _paymentService.getTotalPaidForBill(bill.id);
      balances[bill.id] = bill.finalPrice - totalPaid;
    }
    if (mounted) {
      setState(() {
        _balances = balances;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt, color: Colors.purple.shade700, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Select Bill to Pay',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.bills.length,
                itemBuilder: (context, index) {
                  final bill = widget.bills[index];
                  final balance = _balances[bill.id] ?? bill.finalPrice;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple.shade100,
                        child: Icon(Icons.receipt, color: Colors.purple.shade700),
                      ),
                      title: Text(
                        bill.billNumber ?? 'Bill #${bill.id.substring(0, 8).toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Final: ${widget.currencyFormatter.format(bill.finalPrice)}'),
                          Text(
                            'Balance: ${widget.currencyFormatter.format(balance)}',
                            style: TextStyle(
                              color: balance > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      trailing: balance > 0
                          ? ElevatedButton(
                              onPressed: () => Navigator.pop(context, bill),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Select'),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Paid',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
