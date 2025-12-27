import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_payment.dart';
import '../services/buyer_payment_service.dart';

class ManualPaymentDialog extends StatefulWidget {
  final List<BuyerBill> bills;
  final NumberFormat currencyFormatter;
  final BuyerPaymentService paymentService;
  final double totalBalanceDue;

  const ManualPaymentDialog({
    super.key,
    required this.bills,
    required this.currencyFormatter,
    required this.paymentService,
    required this.totalBalanceDue,
  });

  @override
  State<ManualPaymentDialog> createState() => _ManualPaymentDialogState();
}

class _ManualPaymentDialogState extends State<ManualPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');

  DateTime? _paymentDate;
  String _paymentType = 'cash';
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _accountTitleController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountHolderNameController = TextEditingController();
  final TextEditingController _referenceNumberController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _paymentDate = DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _accountTitleController.dispose();
    _bankNameController.dispose();
    _accountHolderNameController.dispose();
    _referenceNumberController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _paymentDate) {
      setState(() {
        _paymentDate = picked;
      });
    }
  }

  Future<void> _savePayment() async {
    if (_formKey.currentState!.validate()) {
      if (_paymentDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select payment date'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final amount = double.parse(_amountController.text);
      if (amount > widget.totalBalanceDue) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Amount cannot exceed balance due: ${widget.currencyFormatter.format(widget.totalBalanceDue)}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        // Get bills with their balances, sorted by oldest first
        final List<Map<String, dynamic>> billsWithBalance = [];
        for (var bill in widget.bills) {
          final totalPaid = await widget.paymentService.getTotalPaidForBill(bill.id);
          final balance = bill.finalPrice - totalPaid;
          if (balance > 0) {
            billsWithBalance.add({
              'bill': bill,
              'balance': balance,
            });
          }
        }
        
        // Sort by date (oldest first)
        billsWithBalance.sort((a, b) {
          final aBill = a['bill'] as BuyerBill;
          final bBill = b['bill'] as BuyerBill;
          return aBill.createdAt.compareTo(bBill.createdAt);
        });

        // Allocate payment to bills (oldest first)
        double remainingAmount = amount;
        for (var billData in billsWithBalance) {
          if (remainingAmount <= 0) break;
          
          final bill = billData['bill'] as BuyerBill;
          final balance = billData['balance'] as double;
          final paymentAmount = remainingAmount > balance ? balance : remainingAmount;
          
          final payment = BuyerPayment(
            id: const Uuid().v4(),
            billId: bill.id,
            paymentDate: _paymentDate!,
            paymentType: _paymentType,
            amount: paymentAmount,
            accountTitle: _paymentType == 'bank_transfer' && _accountTitleController.text.trim().isNotEmpty
                ? _accountTitleController.text.trim()
                : null,
            bankName: _paymentType == 'bank_transfer' && _bankNameController.text.trim().isNotEmpty
                ? _bankNameController.text.trim()
                : null,
            accountHolderName: _paymentType == 'bank_transfer' && _accountHolderNameController.text.trim().isNotEmpty
                ? _accountHolderNameController.text.trim()
                : null,
            referenceNumber: _paymentType == 'bank_transfer' && _referenceNumberController.text.trim().isNotEmpty
                ? _referenceNumberController.text.trim()
                : null,
            createdAt: DateTime.now(),
          );

          await widget.paymentService.addPayment(payment);
          remainingAmount -= paymentAmount;
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment of ${widget.currencyFormatter.format(amount)} added successfully'),
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
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.payment, color: Colors.green.shade700, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Add Payment',
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
              // Balance Due Display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Balance Due:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      widget.currencyFormatter.format(widget.totalBalanceDue),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [

                      // Payment Date
                      InkWell(
                        onTap: () => _selectDate(context),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Payment Date *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            _paymentDate != null
                                ? _dateFormatter.format(_paymentDate!)
                                : 'Select date',
                            style: TextStyle(
                              color: _paymentDate != null
                                  ? Colors.black
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Payment Type
                      DropdownButtonFormField<String>(
                        value: _paymentType,
                        decoration: const InputDecoration(
                          labelText: 'Payment Type *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.payment),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'cash',
                            child: Text('Cash'),
                          ),
                          DropdownMenuItem(
                            value: 'bank_transfer',
                            child: Text('Bank Transfer'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _paymentType = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      TextFormField(
                        controller: _amountController,
                        decoration: InputDecoration(
                          labelText: 'Amount *',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.currency_rupee),
                          prefixText: 'Rs. ',
                          helperText: 'Max: ${widget.currencyFormatter.format(widget.totalBalanceDue)}',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter amount';
                          }
                          final amount = double.tryParse(value);
                          if (amount == null || amount <= 0) {
                            return 'Enter valid amount';
                          }
                          if (amount > widget.totalBalanceDue) {
                            return 'Amount exceeds balance due';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Bank Transfer Fields
                      if (_paymentType == 'bank_transfer') ...[
                        TextFormField(
                          controller: _accountTitleController,
                          decoration: const InputDecoration(
                            labelText: 'Account Title *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.account_circle),
                          ),
                          validator: (value) {
                            if (_paymentType == 'bank_transfer' && (value == null || value.trim().isEmpty)) {
                              return 'Enter account title';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _bankNameController,
                          decoration: const InputDecoration(
                            labelText: 'Bank Name *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.account_balance),
                          ),
                          validator: (value) {
                            if (_paymentType == 'bank_transfer' && (value == null || value.trim().isEmpty)) {
                              return 'Enter bank name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _accountHolderNameController,
                          decoration: const InputDecoration(
                            labelText: 'Account Holder Name *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (value) {
                            if (_paymentType == 'bank_transfer' && (value == null || value.trim().isEmpty)) {
                              return 'Enter account holder name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _referenceNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Reference Number *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.receipt),
                          ),
                          validator: (value) {
                            if (_paymentType == 'bank_transfer' && (value == null || value.trim().isEmpty)) {
                              return 'Enter reference number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _savePayment,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Add Payment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
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
