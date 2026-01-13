import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_bill_item.dart';
import '../services/buyer_bill_service.dart';

class ManualBillDialog extends StatefulWidget {
  final Buyer buyer;
  final NumberFormat currencyFormatter;

  const ManualBillDialog({
    super.key,
    required this.buyer,
    required this.currencyFormatter,
  });

  @override
  State<ManualBillDialog> createState() => _ManualBillDialogState();
}

class _ManualBillDialogState extends State<ManualBillDialog> {
  final _formKey = GlobalKey<FormState>();
  final _billService = BuyerBillService();
  final _amountController = TextEditingController();
  final _expenseController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  bool _isLoading = false;
  double _totalAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_updateTotal);
    _expenseController.addListener(_updateTotal);
  }

  void _updateTotal() {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final expense = double.tryParse(_expenseController.text.replaceAll(',', '')) ?? 0.0;
    setState(() {
      _totalAmount = amount + expense;
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_updateTotal);
    _expenseController.removeListener(_updateTotal);
    _amountController.dispose();
    _expenseController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateBillNumber() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return 'BILL-$year$month$day-$hour$minute$second';
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final amount = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
      final expense = double.tryParse(_expenseController.text.replaceAll(',', '')) ?? 0.0;
      final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

      if (amount <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Amount must be greater than 0'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Create a single item for the manual bill
      final item = BuyerBillItem(
        id: const Uuid().v4(),
        itemName: 'Manual Bill Entry',
        price: amount,
        unit: '1',
        quantity: 1.0,
        expense: expense,
        subtotal: amount + expense,
      );

      // Create the bill
      final bill = BuyerBill(
        id: const Uuid().v4(),
        buyerId: widget.buyer.id,
        buyerName: widget.buyer.name,
        items: [item],
        total: amount,
        totalExpense: expense,
        finalPrice: amount + expense,
        amountPaid: 0.0,
        change: 0.0,
        createdAt: DateTime.now(),
        paymentMethod: 'cash',
        notes: notes,
        billNumber: _generateBillNumber(),
      );

      await _billService.addBill(bill);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Manual bill created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.receipt_long,
                    color: Colors.purple.shade700,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add Manual Bill',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Buyer: ${widget.buyer.name}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Bill Amount *',
                  hintText: 'Enter amount',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter bill amount';
                  }
                  final amount = double.tryParse(value.replaceAll(',', ''));
                  if (amount == null || amount <= 0) {
                    return 'Amount must be greater than 0';
                  }
                  return null;
                },
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _expenseController,
                decoration: InputDecoration(
                  labelText: 'Expense (Optional)',
                  hintText: 'Enter expense amount',
                  prefixIcon: const Icon(Icons.money_off),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final expense = double.tryParse(value.replaceAll(',', ''));
                    if (expense != null && expense < 0) {
                      return 'Expense cannot be negative';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Add any notes',
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Final Amount:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      widget.currencyFormatter.format(_totalAmount),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveBill,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Create Bill'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
