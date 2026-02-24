import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/buyer.dart';
import '../models/buyer_bill.dart';
import '../models/buyer_bill_item.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../services/buyer_bill_service.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';

class CreateEditBuyerBillScreen extends StatefulWidget {
  final Buyer buyer;
  final BuyerBill? bill;

  const CreateEditBuyerBillScreen({
    super.key,
    required this.buyer,
    this.bill,
  });

  @override
  State<CreateEditBuyerBillScreen> createState() => _CreateEditBuyerBillScreenState();
}

class _CreateEditBuyerBillScreenState extends State<CreateEditBuyerBillScreen> {
  final _billService = BuyerBillService();
  final _productService = ProductService();
  final _formKey = GlobalKey<FormState>();
  final List<BuyerBillItem> _items = [];
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');
  
  String _paymentMethod = 'cash';
  String? _notes;
  double _amountPaid = 0.0;
  bool _isLoading = false;
  late TextEditingController _billNumberController;
  late TextEditingController _finalPriceWithoutExpenseController;

  @override
  void initState() {
    super.initState();
    if (widget.bill != null) {
      _items.addAll(widget.bill!.items);
      _paymentMethod = widget.bill!.paymentMethod;
      _notes = widget.bill!.notes;
      _amountPaid = widget.bill!.amountPaid;
      _billNumberController = TextEditingController(
        text: widget.bill!.billNumber ?? '',
      );
      _finalPriceWithoutExpenseController = TextEditingController(
        text: widget.bill!.finalPrice.toStringAsFixed(2),
      );
    } else {
      // Auto-generate bill number for new bills
      _billNumberController = TextEditingController(
        text: _generateBillNumber(),
      );
      _finalPriceWithoutExpenseController = TextEditingController(text: '');
    }
  }

  void _syncFinalPriceWithoutExpenseFromTotal() {
    if (_items.isEmpty) {
      _finalPriceWithoutExpenseController.text = '';
    } else {
      _finalPriceWithoutExpenseController.text = _total.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _billNumberController.dispose();
    _finalPriceWithoutExpenseController.dispose();
    super.dispose();
  }

  String _generateBillNumber() {
    // Generate bill number: BILL-YYYYMMDD-HHMMSS
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return 'BILL-$year$month$day-$hour$minute$second';
  }

  double get _total {
    // Use the saved subtotal (which respects manual total price edits) minus expenses
    // subtotal = totalPrice + expense, so subtotal - expense = totalPrice
    return _items.fold(0.0, (sum, item) => sum + (item.subtotal - item.expense));
  }

  double get _totalExpense {
    return _items.fold(0.0, (sum, item) => sum + item.expense);
  }

  double get _finalPrice {
    return _total + _totalExpense;
  }

  double get _change {
    return 0.0; // Not used anymore
  }

  double get _balanceDue {
    return 0.0; // Not used anymore
  }

  void _addItem() {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        onAdd: (item) {
          setState(() {
            _items.add(item);
            _syncFinalPriceWithoutExpenseFromTotal();
          });
        },
      ),
    );
  }

  void _editItem(int index) {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        item: _items[index],
        onAdd: (item) {
          setState(() {
            _items[index] = item;
            _syncFinalPriceWithoutExpenseFromTotal();
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _syncFinalPriceWithoutExpenseFromTotal();
    });
  }

  /// Updates product stock when bill is created/updated. For buyer bills, stock INCREASES.
  Future<void> _updateProductStockForBill() async {
    final oldItems = widget.bill?.items ?? [];

    // Reverse old items' stock contribution (when editing)
    for (final item in oldItems) {
      await _reverseItemStock(item);
    }

    // Add new items' stock contribution
    for (final item in _items) {
      await _addItemStock(item);
    }
  }

  Future<void> _reverseItemStock(BuyerBillItem item) async {
    final name = item.itemName.trim();
    if (name.isEmpty) return;

    final oldQuantity = item.quantity;
    final oldPrice = item.price;
    final oldExpense = item.expense;
    final oldPackSize = item.packSize;
    final oldBonusQty = item.bonusQty;
    final oldHadPacking = (item.packingType != null && item.packingType!.trim().isNotEmpty) || (oldPackSize > 1);
    final oldTotalUnits = (oldHadPacking && oldPackSize > 0) ? (oldQuantity * oldPackSize) + oldBonusQty : oldQuantity + oldBonusQty;
    final oldTotalValue = (oldPrice * oldQuantity) + oldExpense;

    Product? product;
    try {
      final products = await _productService.searchProducts(name);
      for (final p in products) {
        if (p.name.toLowerCase() == name.toLowerCase()) {
          product = p;
          break;
        }
      }
    } catch (_) {
      return;
    }
    if (product == null) return;

    final stockBefore = (product.stock - oldTotalUnits).clamp(0.0, double.infinity);
    final totalValueBefore = (product.stock * product.purchasePrice) - oldTotalValue;
    final avgPrice = stockBefore > 0 ? totalValueBefore / stockBefore : product.purchasePrice;

    await _productService.updateProduct(product.copyWith(
      stock: stockBefore,
      purchasePrice: avgPrice,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> _addItemStock(BuyerBillItem item) async {
    final name = item.itemName.trim();
    if (name.isEmpty) return;

    final quantity = item.quantity;
    final price = item.price;
    final expense = item.expense;
    final packSize = item.packSize;
    final bonusQty = item.bonusQty;
    final hasPacking = (item.packingType != null && item.packingType!.trim().isNotEmpty) || packSize > 1;
    final baseUnits = (hasPacking && packSize > 0) ? (quantity * packSize) : quantity;
    final totalUnits = baseUnits + bonusQty;
    final totalValue = (price * quantity) + expense;
    final unitCost = baseUnits > 0 ? totalValue / baseUnits : (hasPacking && packSize > 0 ? price / packSize : price);
    final category = item.category;

    Product? product;
    try {
      final products = await _productService.searchProducts(name);
      for (final p in products) {
        if (p.name.toLowerCase() == name.toLowerCase()) {
          product = p;
          break;
        }
      }
    } catch (_) {
      product = null;
    }

    if (product != null) {
      final oldStock = product.stock;
      final oldPrice = product.purchasePrice;
      final oldValue = oldStock * oldPrice;
      final newStock = oldStock + totalUnits;
      final newValue = oldValue + (totalUnits * unitCost);
      final avgPrice = newStock > 0 ? newValue / newStock : unitCost;
      await _productService.updateProduct(product.copyWith(
        stock: newStock,
        purchasePrice: avgPrice,
        updatedAt: DateTime.now(),
      ));
    } else if (category != null && category.isNotEmpty) {
      final newProduct = Product(
        id: const Uuid().v4(),
        name: name,
        purchasePrice: unitCost,
        salePrice: unitCost * 1.1,
        stock: totalUnits,
        unit: 'pcs',
        category: category,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _productService.addProduct(newProduct);
    }
  }

  Future<void> _saveBill() async {
    // Validate form first (includes bill number validation)
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if items are empty
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item to create a bill'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validate bill number is not empty (double check)
    final billNumber = _billNumberController.text.trim();
    if (billNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a bill number'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Update product stock when bill is created/updated (not when adding items)
      await _updateProductStockForBill();

      final priceWithoutExpense = double.tryParse(
            _finalPriceWithoutExpenseController.text.trim()) ?? _total;
      final bill = BuyerBill(
        id: widget.bill?.id ?? const Uuid().v4(),
        buyerId: widget.buyer.id,
        buyerName: widget.buyer.name,
        items: _items,
        total: _total,
        totalExpense: _totalExpense,
        finalPrice: priceWithoutExpense, // Manual or calculated (used for balance)
        amountPaid: widget.bill?.amountPaid ?? 0.0, // Keep existing or default to 0
        change: widget.bill?.change ?? 0.0, // Keep existing or default to 0
        createdAt: widget.bill?.createdAt ?? DateTime.now(),
        paymentMethod: widget.bill?.paymentMethod ?? 'cash', // Keep existing or default to cash
        notes: _notes?.trim().isEmpty == true ? null : _notes,
        billNumber: billNumber.isEmpty ? null : billNumber,
      );

      await _billService.addBill(bill);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.bill == null
                  ? 'Bill created successfully'
                  : 'Bill updated successfully',
            ),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bill == null ? 'Create Bill' : 'Edit Bill'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Buyer Info and Bill Number
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.purple.shade50,
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.purple.shade100,
                        child: Icon(Icons.person, color: Colors.purple.shade700),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.buyer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (widget.buyer.phone != null)
                              Text(
                                widget.buyer.phone!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _billNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Bill Number *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                      helperText: 'Enter bill number or use auto-generated',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a bill number';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),

            // Items List
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart_outlined,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text(
                            'No items added',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap the button below to add items',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final packSize = item.packSize > 0 ? item.packSize : 1.0;
                        final totalQty = (item.quantity * packSize) + item.bonusQty;
                        final unitPrice = item.packSize > 1 ? (item.price / item.packSize) : item.price;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              item.itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.quantity} ${item.unit} × ${_currencyFormatter.format(item.price)}',
                                ),
                                Text(
                                  'Total Qty: ${totalQty % 1 == 0 ? totalQty.toInt() : totalQty.toStringAsFixed(2)}  •  Unit Price: ${_currencyFormatter.format(unitPrice)}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                ),
                                Text(
                                  'Total: ${_currencyFormatter.format(item.subtotal - item.expense)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                                if (item.expense > 0)
                                  Text(
                                    'Expense: ${_currencyFormatter.format(item.expense)}',
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                if (item.date != null)
                                  Text(
                                    'Date: ${DateFormat('MMM dd, yyyy').format(item.date!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _currencyFormatter.format(item.subtotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _editItem(index),
                                  color: Colors.blue,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () => _removeItem(index),
                                  color: Colors.red,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Summary and Payment
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Totals
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:'),
                      Text(
                        _currencyFormatter.format(_total),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Expense:'),
                      Text(
                        _currencyFormatter.format(_totalExpense),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('Final Price (without expense):'),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: _finalPriceWithoutExpenseController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                              ],
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.calculate),
                            tooltip: 'Calculator',
                            onPressed: () async {
                              final v = await _CalculatorDialog.show(
                                context,
                                initialValue: _finalPriceWithoutExpenseController.text,
                              );
                              if (v != null && mounted) {
                                _finalPriceWithoutExpenseController.text = v.toStringAsFixed(2);
                                setState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Final Price (with expense):',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _currencyFormatter.format(_finalPrice),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Notes - Show for both create and edit
                  TextFormField(
                    initialValue: _notes,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 2,
                    onChanged: (value) {
                      _notes = value;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveBill,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(widget.bill == null ? 'Create Bill' : 'Update Bill'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        backgroundColor: Colors.purple,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Simple calculator dialog for plus, minus, multiply, divide. Returns result when "Use" is pressed.
class _CalculatorDialog extends StatefulWidget {
  final String initialValue;

  const _CalculatorDialog({this.initialValue = '0'});

  static Future<double?> show(BuildContext context, {String initialValue = ''}) {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CalculatorDialog(
        initialValue: initialValue.isEmpty ? '0' : initialValue,
      ),
    );
  }

  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
  String _display = '0';
  double? _pendingValue;
  String? _pendingOp;

  @override
  void initState() {
    super.initState();
    _display = widget.initialValue;
  }

  void _onDigit(String d) {
    setState(() {
      if (d == '.') {
        if (_display.contains('.')) return;
        if (_display == '0') _display = '0.';
        else _display += '.';
        return;
      }
      if (d == '00') {
        if (_display == '0') return;
        _display += '00';
        return;
      }
      if (_display == '0') _display = d;
      else _display += d;
    });
  }

  void _onOp(String op) {
    setState(() {
      final current = double.tryParse(_display) ?? 0.0;
      if (_pendingOp != null && _pendingValue != null) {
        final result = _apply(_pendingValue!, _pendingOp!, current);
        _display = _formatNum(result);
        _pendingValue = result;
      } else {
        _pendingValue = current;
      }
      _pendingOp = op;
      _display = '0';
    });
  }

  double _apply(double a, String op, double b) {
    switch (op) {
      case '+': return a + b;
      case '-': return a - b;
      case '×': return a * b;
      case '÷': return b == 0 ? a : a / b;
      case '%': return a * (b / 100);
      default: return b;
    }
  }

  String _formatNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  void _onEquals() {
    if (_pendingOp == null || _pendingValue == null) return;
    setState(() {
      final current = double.tryParse(_display) ?? 0.0;
      final result = _apply(_pendingValue!, _pendingOp!, current);
      _display = _formatNum(result);
      _pendingValue = null;
      _pendingOp = null;
    });
  }

  void _onClear() {
    setState(() {
      _display = '0';
      _pendingValue = null;
      _pendingOp = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.calculate, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          const Text('Calculator'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerRight,
            child: Text(
              _display,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Table(
            children: [
              TableRow(children: [
                _calcBtn('C', Colors.pink, _onClear),
                _calcBtn('%', Colors.blue.shade300, () => _onOp('%')),
                _calcBtn('÷', Colors.orange, () => _onOp('÷')),
                _calcBtn('×', Colors.orange, () => _onOp('×')),
              ]),
              TableRow(children: [
                _calcBtn('7', Colors.grey.shade300, () => _onDigit('7')),
                _calcBtn('8', Colors.grey.shade300, () => _onDigit('8')),
                _calcBtn('9', Colors.grey.shade300, () => _onDigit('9')),
                _calcBtn('-', Colors.orange, () => _onOp('-')),
              ]),
              TableRow(children: [
                _calcBtn('4', Colors.grey.shade300, () => _onDigit('4')),
                _calcBtn('5', Colors.grey.shade300, () => _onDigit('5')),
                _calcBtn('6', Colors.grey.shade300, () => _onDigit('6')),
                _calcBtn('+', Colors.orange, () => _onOp('+')),
              ]),
              TableRow(children: [
                _calcBtn('1', Colors.grey.shade300, () => _onDigit('1')),
                _calcBtn('2', Colors.grey.shade300, () => _onDigit('2')),
                _calcBtn('3', Colors.grey.shade300, () => _onDigit('3')),
                _calcBtn('=', Colors.green, _onEquals),
              ]),
              TableRow(children: [
                _calcBtn('0', Colors.grey.shade300, () => _onDigit('0')),
                _calcBtn('00', Colors.grey.shade300, () => _onDigit('00')),
                _calcBtn('.', Colors.grey.shade300, () => _onDigit('.')),
                _calcBtn('Use', Colors.green, () {
                  final v = double.tryParse(_display);
                  Navigator.of(context).pop(v ?? 0.0);
                }),
              ]),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _calcBtn(String label, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: label.length > 2 ? 14 : 20,
                fontWeight: FontWeight.bold,
                color: color == Colors.grey.shade300 ? Colors.black87 : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  final BuyerBillItem? item;
  final Function(BuyerBillItem) onAdd;

  const _AddItemDialog({
    this.item,
    required this.onAdd,
  });

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _productService = ProductService();
  final _categoryService = CategoryService();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _quantityController;
  late TextEditingController _unitController;
  late TextEditingController _expenseController;
  late TextEditingController _totalPriceController;
  late TextEditingController _productSearchController;
  late TextEditingController _packSizeController;
  late TextEditingController _singleUnitPriceController;
  late TextEditingController _totalQtyController;
  late TextEditingController _bonusQtyController;
  late TextEditingController _taxPercentController;
  bool _isSyncingQtyPackSize = false;
  DateTime? _selectedDate;
  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');
  bool _isManualTotalEdit = false;
  String? _selectedCategory;
  Product? _selectedProduct;
  double? _currentProductStock; // Track current stock for real-time updates
  String? _selectedPackingType;
  final List<String> _packingTypes = [
    'Box',
    'Carton',
    'Packet',
    'Bag',
    'Bottle',
    'Can',
    'Piece',
    'Bundle',
    'Case',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.itemName ?? '');
    _priceController = TextEditingController(
        text: widget.item?.price.toString() ?? '');
    _quantityController = TextEditingController(
        text: widget.item?.quantity.toString() ?? '1');
    _unitController = TextEditingController(text: widget.item?.unit ?? '');
    _expenseController = TextEditingController(
        text: widget.item?.expense.toString() ?? '0');
    _productSearchController = TextEditingController();
    final initPackSize = widget.item?.packSize ?? 1.0;
    _packSizeController = TextEditingController(
        text: initPackSize % 1 == 0
            ? initPackSize.toInt().toString()
            : initPackSize.toStringAsFixed(2));
    _singleUnitPriceController = TextEditingController();
    _totalQtyController = TextEditingController();
    _bonusQtyController = TextEditingController(
        text: ((widget.item?.bonusQty ?? 0) % 1 == 0
            ? (widget.item?.bonusQty ?? 0).toInt().toString()
            : (widget.item?.bonusQty ?? 0).toStringAsFixed(2)));
    _taxPercentController = TextEditingController(text: '0');
    _selectedDate = widget.item?.date ?? DateTime.now();
    // Restore packing type when editing (match unit to packing types if applicable)
    _selectedPackingType = widget.item?.packingType;
    if (_selectedPackingType == null && widget.item?.unit != null) {
      final unit = widget.item!.unit.trim();
      if (_packingTypes.any((t) => t.toLowerCase() == unit.toLowerCase())) {
        _selectedPackingType = _packingTypes.firstWhere(
            (t) => t.toLowerCase() == unit.toLowerCase());
      }
    }
    
    // Initialize total price controller (buyer total = (Price × Quantity) × (1 + Tax%); expense is your cost)
    final initialPrice = double.tryParse(_priceController.text) ?? 0.0;
    final initialQuantity = double.tryParse(_quantityController.text) ?? 0.0;
    final initialTaxMult = 1.0 + ((double.tryParse(_taxPercentController.text) ?? 0.0) / 100.0);
    final initialTotal = (initialPrice * initialQuantity) * initialTaxMult;
    _totalPriceController = TextEditingController(
        text: initialTotal > 0 ? initialTotal.toStringAsFixed(2) : '');
    
    // Add listeners to recalculate total when price or quantity changes
    _priceController.addListener(_onPriceOrQuantityChanged);
    _quantityController.addListener(_onPriceOrQuantityChanged);
    
    // Add listener to recalculate price when total is manually changed
    _totalPriceController.addListener(_onTotalPriceChanged);
    
    // Add listener to update total price when expense changes
    _expenseController.addListener(_onExpenseChanged);
    
    // Add listener for product search
    _productSearchController.addListener(_onProductSearchChanged);
    
    // Add listeners to update single unit price
    _priceController.addListener(_updateSingleUnitPrice);
    _packSizeController.addListener(_updateSingleUnitPrice);
    _quantityController.addListener(_updateSingleUnitPrice);
    _expenseController.addListener(_updateSingleUnitPrice);
    _taxPercentController.addListener(_onTaxPercentChanged);

    // Add listeners to update total qty (Qty × Pack Size + Bonus)
    _quantityController.addListener(_updateTotalQty);
    _packSizeController.addListener(_updateTotalQty);
    _bonusQtyController.addListener(_updateTotalQty);
    _totalQtyController.addListener(_onTotalQtyChanged);
    
    // Load product stock if editing existing item
    if (widget.item != null && _nameController.text.isNotEmpty) {
      _loadProductStockByName(_nameController.text);
    }
    
    // Calculate initial single unit price
    _updateSingleUnitPrice();

    // Calculate initial total qty
    _updateTotalQty();
  }
  
  Future<void> _loadProductStockByName(String productName) async {
    // Search for product by name to get current stock
    try {
      final products = await _productService.searchProducts(productName);
      final matchingProduct = products.firstWhere(
        (p) => p.name.toLowerCase() == productName.toLowerCase(),
        orElse: () => products.isNotEmpty ? products.first : throw StateError('Product not found'),
      );
      
      if (mounted) {
        setState(() {
          _selectedProduct = matchingProduct;
          _currentProductStock = matchingProduct.stock;
          _productSearchController.text = matchingProduct.name;
          // When editing, restore category from product so dropdown shows correct value
          if (widget.item != null && matchingProduct.category.isNotEmpty) {
            _selectedCategory = matchingProduct.category;
          }
        });
      }
    } catch (e) {
      // Product not found or error loading - continue without stock info
      print('Could not load product stock: $e');
    }
  }
  
  void _onProductSearchChanged() {
    // Trigger rebuild to update filtered products
    setState(() {});
  }
  
  void _onCategorySelected(String? category) {
    setState(() {
      _selectedCategory = category;
      _selectedProduct = null;
      _productSearchController.clear();
      _nameController.clear();
      _priceController.clear();
      _unitController.clear();
    });
  }
  
  List<Product> _getFilteredProducts(List<Product> allProducts) {
    var products = allProducts;
    
    // Filter by category if selected (case-insensitive matching)
    if (_selectedCategory != null) {
      final selectedCategoryLower = _selectedCategory!.trim().toLowerCase();
      products = products.where((p) {
        final productCategoryLower = p.category.trim().toLowerCase();
        return productCategoryLower == selectedCategoryLower;
      }).toList();
      
      // Debug: Print category matching info
      if (products.isEmpty && allProducts.isNotEmpty) {
        // Get unique categories from all products for debugging
        final uniqueCategories = allProducts.map((p) => p.category).toSet().toList();
        print('Selected category: "$_selectedCategory"');
        print('Available categories in products: $uniqueCategories');
        print('Total products: ${allProducts.length}');
        print('Filtered products: ${products.length}');
      }
    }
    
    // Filter by search query if any
    final query = _productSearchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      products = products.where((product) {
        return product.name.toLowerCase().contains(query) ||
            (product.barcode?.toLowerCase().contains(query) ?? false) ||
            (product.description?.toLowerCase().contains(query) ?? false);
      }).toList();
    }
    
    return products;
  }
  
  bool _shouldShowProductList() {
    // Show products if:
    // 1. A category is selected (show all products in that category)
    // 2. OR search query is not empty (show filtered results)
    return _selectedCategory != null || _productSearchController.text.isNotEmpty;
  }
  
  void _onProductSelected(Product product) async {
    // Get latest product stock
    final latestProduct = await _productService.getProductById(product.id);
    setState(() {
      _selectedProduct = latestProduct ?? product;
      _currentProductStock = _selectedProduct!.stock;
      _nameController.text = _selectedProduct!.name;
      // Use purchase price instead of sale price for buyer bills
      _priceController.text = _selectedProduct!.purchasePrice.toStringAsFixed(2);
      _unitController.text = _selectedProduct!.unit;
      _productSearchController.text = _selectedProduct!.name;
    });
    _onPriceOrQuantityChanged();
  }
  
  void _updateStockInfo() async {
    if (_selectedProduct != null) {
      final latestProduct = await _productService.getProductById(_selectedProduct!.id);
      if (latestProduct != null && mounted) {
        setState(() {
          _currentProductStock = latestProduct.stock;
          _selectedProduct = latestProduct;
        });
      }
    }
  }
  
  double _getTaxMultiplier() {
    final taxPercent = double.tryParse(_taxPercentController.text) ?? 0.0;
    return 1.0 + (taxPercent / 100.0);
  }

  void _onTaxPercentChanged() {
    _onPriceOrQuantityChanged();
    _updateSingleUnitPrice();
  }

  void _onPriceOrQuantityChanged() {
    // Only auto-calculate total if user hasn't manually edited it recently
    // Buyer bill: Total Price = (Price × Quantity) × (1 + Tax%) ; expense is your cost, not added to buyer total
    if (!_isManualTotalEdit) {
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final quantity = double.tryParse(_quantityController.text) ?? 0.0;
      final baseTotal = price * quantity;
      final taxMult = _getTaxMultiplier();
      final calculatedTotal = baseTotal * taxMult;
      
      // Temporarily remove listeners to avoid recursive updates
      _totalPriceController.removeListener(_onTotalPriceChanged);
      _totalPriceController.text = calculatedTotal > 0 ? calculatedTotal.toStringAsFixed(2) : '';
      _totalPriceController.addListener(_onTotalPriceChanged);
    }
    
    // Update stock info when quantity changes
    _updateStockInfo();
  }

  void _onExpenseChanged() {
    // Total Price for buyer = (Price × Quantity) × (1 + Tax%); expense does not change buyer total
    if (!_isManualTotalEdit && mounted) {
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final quantity = double.tryParse(_quantityController.text) ?? 0.0;
      final baseTotal = price * quantity;
      final taxMult = _getTaxMultiplier();
      final calculatedTotal = baseTotal * taxMult;
      
      // Temporarily remove listener to avoid recursive updates
      _totalPriceController.removeListener(_onTotalPriceChanged);
      _totalPriceController.text = calculatedTotal > 0 ? calculatedTotal.toStringAsFixed(2) : '';
      _totalPriceController.addListener(_onTotalPriceChanged);
      
      // Force UI update (e.g. Single Unit Price changes with expense)
      setState(() {});
    }
  }
  
  void _onTotalPriceChanged() {
    // When total price is manually changed, recalculate the price field (base price before tax)
    // Total Price shown = (Price × Quantity) × (1 + Tax%), so base price = totalPrice / (quantity * taxMult)
    final totalPrice = double.tryParse(_totalPriceController.text) ?? 0.0;
    final quantity = double.tryParse(_quantityController.text) ?? 1.0;
    final taxMult = _getTaxMultiplier();
    
    if (totalPrice > 0 && quantity > 0 && taxMult > 0) {
      _isManualTotalEdit = true;
      final baseTotal = totalPrice / taxMult;
      final newPrice = baseTotal / quantity;
      
      // Temporarily remove listener to avoid recursive updates
      _priceController.removeListener(_onPriceOrQuantityChanged);
      _priceController.text = newPrice > 0 ? newPrice.toStringAsFixed(2) : '';
      _priceController.addListener(_onPriceOrQuantityChanged);
    }
  }
  
  void _resetToCalculated() {
    setState(() {
      _isManualTotalEdit = false;
      _onPriceOrQuantityChanged();
    });
  }
  
  void _updateSingleUnitPrice() {
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final packSize = double.tryParse(_packSizeController.text) ?? 1.0;
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    final expense = double.tryParse(_expenseController.text) ?? 0.0;
    final hasPacking = (_selectedPackingType != null && _selectedPackingType!.trim().isNotEmpty);
    final taxMult = _getTaxMultiplier();
    
    // Buyer total (tax-inclusive) = (price * qty) * taxMult. Expense is our cost, not added to buyer.
    // Single unit price (buyer-facing, tax-inclusive) = buyer total / total units.
    final totalUnits = (hasPacking && packSize > 0) ? (qty * packSize) : qty;
    final buyerTotal = (price * qty) * taxMult;
    final totalCostForUnit = buyerTotal + expense; // cost includes expense for our records

    if (totalUnits > 0 && totalCostForUnit > 0) {
      final singleUnitPrice = totalCostForUnit / totalUnits;
      _singleUnitPriceController.text = singleUnitPrice.toStringAsFixed(2);
    } else if (totalUnits > 0 && buyerTotal > 0) {
      _singleUnitPriceController.text = (buyerTotal / totalUnits).toStringAsFixed(2);
    } else {
      _singleUnitPriceController.text = '';
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  void _updateTotalQty() {
    if (_isSyncingQtyPackSize) return;
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    final packSize = double.tryParse(_packSizeController.text) ?? 0.0;
    final bonusQty = double.tryParse(_bonusQtyController.text) ?? 0.0;

    final baseQty = (qty > 0 && packSize > 0) ? qty * packSize : 0.0;
    final totalQty = baseQty + bonusQty;

    _isSyncingQtyPackSize = true;
    _totalQtyController.text = totalQty > 0
        ? totalQty.toStringAsFixed(totalQty % 1 == 0 ? 0 : 2)
        : '';
    _isSyncingQtyPackSize = false;

    if (mounted) {
      setState(() {});
    }
  }

  void _onTotalQtyChanged() {
    if (_isSyncingQtyPackSize) return;

    final totalQty = double.tryParse(_totalQtyController.text) ?? 0.0;
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    final packSize = double.tryParse(_packSizeController.text) ?? 0.0;
    final baseQty = (qty > 0 && packSize > 0) ? qty * packSize : 0.0;

    // If bonus is used, treat total edit as changing bonus (not pack size)
    final bonusQty = double.tryParse(_bonusQtyController.text) ?? 0.0;
    if (bonusQty != 0 || totalQty > baseQty) {
      final newBonus = (totalQty - baseQty).clamp(0.0, double.infinity);
      _bonusQtyController.removeListener(_updateTotalQty);
      _bonusQtyController.text = newBonus % 1 == 0
          ? newBonus.toInt().toString()
          : newBonus.toStringAsFixed(2);
      _bonusQtyController.addListener(_updateTotalQty);
      if (mounted) setState(() {});
      return;
    }

    // Otherwise back-calc pack size from total
    if (totalQty > 0 && qty > 0) {
      final newPackSize = totalQty / qty;
      _isSyncingQtyPackSize = true;
      _packSizeController.text =
          newPackSize.toStringAsFixed(newPackSize % 1 == 0 ? 0 : 2);
      _isSyncingQtyPackSize = false;
      _updateSingleUnitPrice();
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _priceController.removeListener(_onPriceOrQuantityChanged);
    _quantityController.removeListener(_onPriceOrQuantityChanged);
    _totalPriceController.removeListener(_onTotalPriceChanged);
    _expenseController.removeListener(_onExpenseChanged);
    _productSearchController.removeListener(_onProductSearchChanged);
    _priceController.removeListener(_updateSingleUnitPrice);
    _packSizeController.removeListener(_updateSingleUnitPrice);
    _quantityController.removeListener(_updateSingleUnitPrice);
    _expenseController.removeListener(_updateSingleUnitPrice);
    _quantityController.removeListener(_updateTotalQty);
    _packSizeController.removeListener(_updateTotalQty);
    _bonusQtyController.removeListener(_updateTotalQty);
    _totalQtyController.removeListener(_onTotalQtyChanged);
    _taxPercentController.removeListener(_onTaxPercentChanged);
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _expenseController.dispose();
    _totalPriceController.dispose();
    _productSearchController.dispose();
    _packSizeController.dispose();
    _singleUnitPriceController.dispose();
    _totalQtyController.dispose();
    _bonusQtyController.dispose();
    _taxPercentController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final basePrice = double.parse(_priceController.text); // base price before tax
      final taxMult = _getTaxMultiplier();
      final price = basePrice * taxMult; // tax-inclusive price for line total (price × qty)
      final quantity = double.parse(_quantityController.text); // UI qty (packs if packing selected; otherwise units)
      final packSize = double.tryParse(_packSizeController.text) ?? 1.0;
      final bonusQty = double.tryParse(_bonusQtyController.text) ?? 0.0;
      final hasPacking = (_selectedPackingType != null && _selectedPackingType!.trim().isNotEmpty);

      // Inventory logic:
      // - base units = (packs * packSize) when packing selected, else quantity
      // - totalUnits = base units + bonus (bonus adds to stock but does not affect price)
      // - unitPurchasePrice = (packPrice / packSize) when packing selected, else price
      final baseUnitsForStock = (hasPacking && packSize > 0) ? (quantity * packSize) : quantity;
      final totalUnitsForStock = baseUnitsForStock + bonusQty;
      final unitPurchasePrice = (hasPacking && packSize > 0) ? (price / packSize) : price;

      // Prefer showing packing type as unit label in the bill when selected
      final unit = _unitController.text.trim().isNotEmpty
          ? _unitController.text.trim()
          : (hasPacking ? _selectedPackingType!.trim() : 'pcs');
      final expense = double.tryParse(_expenseController.text) ?? 0.0;
      
      // Total Price in dialog = (Price × Quantity) × (1 + Tax%); already tax-inclusive
      final baseTotalPrice = double.parse(_totalPriceController.text); // buyer amount (tax-inclusive)
      final subtotal = baseTotalPrice + expense; // store full cost (buyer total + expense) for internal use

      // Stock update is deferred until bill is created (see _saveBill)
      // Store category for new product creation at bill save
      final itemCategory = _selectedCategory ?? _selectedProduct?.category;

      final item = BuyerBillItem(
        id: widget.item?.id ?? const Uuid().v4(),
        itemName: name,
        price: price, // keep as pack price if packing selected
        unit: unit, // show packing type when selected
        quantity: quantity, // keep as packs (cartons) when packing selected
        expense: expense,
        subtotal: subtotal,
        date: _selectedDate,
        bonusQty: bonusQty,
        packSize: packSize,
        packingType: _selectedPackingType,
        category: itemCategory,
      );

      widget.onAdd(item);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000), // Allow selecting dates from year 2000
      lastDate: DateTime.now().add(const Duration(days: 365)), // Allow up to 1 year in future
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Add Item' : 'Edit Item'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Category Dropdown
              StreamBuilder<List<Category>>(
                stream: _categoryService.getCategoriesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 56,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  
                  final categories = snapshot.data ?? [];
                  final categoryNames = categories.map((c) => c.name).toList();
                  
                  return DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      helperText: 'Select a category to filter products',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Categories'),
                      ),
                      ...categoryNames.map((name) => DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      )),
                    ],
                    onChanged: _onCategorySelected,
                  );
                },
              ),
              const SizedBox(height: 16),
              
              // Product Search Dropdown
              StreamBuilder<List<Product>>(
                stream: _productService.getProductsStream(),
                builder: (context, snapshot) {
                  final allProducts = snapshot.data ?? [];
                  final filteredProducts = _getFilteredProducts(allProducts);
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _productSearchController,
                        decoration: InputDecoration(
                          labelText: _selectedCategory != null
                              ? 'Search Product in $_selectedCategory *'
                              : 'Search Product *',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _selectedProduct != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _selectedProduct = null;
                                      _nameController.clear();
                                      _priceController.clear();
                                      _unitController.clear();
                                      _productSearchController.clear();
                                    });
                                  },
                                )
                              : null,
                          helperText: _selectedCategory != null
                              ? 'Type to search or see all products below'
                              : 'Select a category first to see products',
                        ),
                        onChanged: (value) {
                          setState(() {});
                        },
                        validator: (value) {
                          if (_selectedProduct == null && _nameController.text.isEmpty) {
                            return 'Please select a product from the list below';
                          }
                          return null;
                        },
                      ),
                      if (_shouldShowProductList())
                        Builder(
                          builder: (context) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(16),
                                child: const Center(child: CircularProgressIndicator()),
                              );
                            }
                            
                            if (filteredProducts.isEmpty) {
                              // Show helpful message based on context
                              String message;
                              final searchText = _productSearchController.text;
                              if (_selectedCategory != null && searchText.isEmpty) {
                                message = 'No products found in "$_selectedCategory" category.\n\nPlease check:\n• Category name matches exactly\n• Products are assigned to this category';
                              } else if (_selectedCategory != null && searchText.isNotEmpty) {
                                message = 'No products found matching "$searchText" in "$_selectedCategory"';
                              } else if (searchText.isNotEmpty) {
                                message = 'No products found matching "$searchText"';
                              } else {
                                message = 'No products available';
                              }
                              
                              return Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  message,
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              );
                            }
                            
                            return Container(
                              margin: const EdgeInsets.only(top: 8),
                              constraints: const BoxConstraints(maxHeight: 200),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = filteredProducts[index];
                                  return InkWell(
                                    onTap: () {
                                      _onProductSelected(product);
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: index < filteredProducts.length - 1 ? 1 : 0,
                                          ),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
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
                                            Row(
                                              children: [
                                                Text(
                                                  'Rs. ${product.purchasePrice.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    color: Colors.purple.shade700,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '| ${product.unit}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: product.stock > 0 ? Colors.green.shade50 : Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: product.stock > 0 ? Colors.green.shade200 : Colors.red.shade200,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Stock: ${product.stock}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: product.stock > 0 ? Colors.green.shade700 : Colors.red.shade700,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (product.barcode != null)
                                              Text(
                                                'Barcode: ${product.barcode}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                          ],
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
                  );
                },
              ),
              const SizedBox(height: 16),
              
              // Item Name (can be manually edited)
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Item Name *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.shopping_bag),
                  helperText: _selectedCategory != null
                      ? 'Auto-filled from product or enter manually (will create new product)'
                      : 'Auto-filled from product or enter manually',
                ),
                onChanged: (value) {
                  // Clear selected product if name is manually changed
                  if (value.trim().toLowerCase() != _selectedProduct?.name.toLowerCase()) {
                    setState(() {
                      _selectedProduct = null;
                      _currentProductStock = null;
                    });
                  }
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter item name';
                  }
                  // If manually entering and category is selected, that's fine
                  // If no category selected, warn user
                  if (_selectedCategory == null && _selectedProduct == null) {
                    return 'Please select a category first or select a product';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Stock Information Display
              if (_selectedProduct != null && _currentProductStock != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _currentProductStock! > 0 ? Colors.green.shade50 : Colors.red.shade50,
                    border: Border.all(
                      color: _currentProductStock! > 0 ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _currentProductStock! > 0 ? Icons.inventory_2 : Icons.inventory_2_outlined,
                        color: _currentProductStock! > 0 ? Colors.green.shade700 : Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Stock: ${_currentProductStock!.toStringAsFixed(2)} ${_selectedProduct!.unit}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _currentProductStock! > 0 ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                            if (_quantityController.text.isNotEmpty)
                              Builder(
                                builder: (context) {
                                  final enteredQty = double.tryParse(_quantityController.text) ?? 0.0;
                                  final enteredPrice = double.tryParse(_priceController.text) ?? 0.0;
                                  final enteredExpense = double.tryParse(_expenseController.text) ?? 0.0;
                                  final packSize = double.tryParse(_packSizeController.text) ?? 1.0;
                                  final hasPacking = (_selectedPackingType != null && _selectedPackingType!.trim().isNotEmpty);
                                  
                                  // Calculate total units being added (cartons × pack size if packing selected, else just qty)
                                  final totalUnitsBeingAdded = (hasPacking && packSize > 0) 
                                      ? (enteredQty * packSize) 
                                      : enteredQty;
                                  
                                  final totalStock = _currentProductStock! + totalUnitsBeingAdded;
                                  
                                  // Calculate weighted average purchase price (including expense)
                                  final oldStock = _currentProductStock!;
                                  final oldPrice = _selectedProduct!.purchasePrice;
                                  final oldTotalValue = oldStock * oldPrice;
                                  // Include expense in the new total value calculation
                                  final newTotalValue = (enteredQty * enteredPrice) + enteredExpense;
                                  final totalValue = oldTotalValue + newTotalValue;
                                  final averagePrice = totalStock > 0 ? totalValue / totalStock : enteredPrice;
                                  
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'After adding: ${totalStock.toStringAsFixed(2)} ${_selectedProduct!.unit} total',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (enteredPrice > 0 && enteredQty > 0)
                                        Text(
                                          'Average purchase price: Rs. ${averagePrice.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w500,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Packing Type and Pack Size Row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedPackingType,
                      decoration: const InputDecoration(
                        labelText: 'Packing Type',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.inventory_2),
                        helperText: 'Select packing type',
                      ),
                      items: _packingTypes.map((type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPackingType = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _packSizeController,
                      decoration: const InputDecoration(
                        labelText: 'Pack Size (no of qty)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                        helperText: 'Quantity per pack',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (value) {
                        setState(() {}); // Trigger rebuild for single unit price calculation
                      },
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          if (double.tryParse(value) == null) {
                            return 'Invalid';
                          }
                          final packSize = double.parse(value);
                          if (packSize <= 0) {
                            return 'Must be > 0';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'Price *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.currency_rupee),
                        prefixText: 'Rs. ',
                        helperText: 'Purchase price',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calculate),
                          tooltip: 'Calculator',
                          onPressed: () async {
                            final v = await _CalculatorDialog.show(
                              context,
                              initialValue: _priceController.text,
                            );
                            if (v != null && mounted) {
                              _priceController.text = v.toStringAsFixed(2);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (value) {
                        setState(() {}); // Trigger rebuild for real-time average price and single unit price calculation
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter price';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Invalid price';
                        }
                        if (double.parse(value) < 0) {
                          return 'Cannot be negative';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: InputDecoration(
                        labelText: _selectedPackingType != null 
                            ? '$_selectedPackingType *' 
                            : 'Qty *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.numbers),
                        helperText: _selectedPackingType != null
                            ? 'Number of $_selectedPackingType to add'
                            : 'Quantity to add to stock',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (value) {
                        setState(() {}); // Trigger rebuild for real-time stock display and total qty
                        _updateTotalQty(); // Also update total qty when quantity changes
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter quantity';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Invalid';
                        }
                        final qty = double.parse(value);
                        if (qty <= 0) {
                          return 'Must be > 0';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tax % Field
              TextFormField(
                controller: _taxPercentController,
                decoration: const InputDecoration(
                  labelText: 'Tax %',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.percent),
                  helperText: 'e.g. 1 or 0.5 for 1% or 0.5% (applied to unit price and total price)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (value) => setState(() {}),
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final v = double.tryParse(value);
                    if (v == null || v < 0) return 'Invalid tax %';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Bonus Qty Field
              TextFormField(
                controller: _bonusQtyController,
                decoration: const InputDecoration(
                  labelText: 'Bonus Qty',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.add_circle_outline),
                  helperText: 'Free quantity added to total (does not affect price)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (value) => setState(() {}),
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (double.tryParse(value) == null) {
                      return 'Invalid';
                    }
                    if (double.parse(value) < 0) {
                      return 'Cannot be negative';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Single Unit Price Field (Read-only, calculated)
              TextFormField(
                controller: _singleUnitPriceController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Single Unit Price',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.attach_money),
                  prefixText: 'Rs. ',
                  filled: true,
                  fillColor: Colors.blue.shade50,
                  helperText: _selectedPackingType != null
                      ? 'Total Price ÷ (Pack Size × $_selectedPackingType)'
                      : 'Total Price ÷ (Pack Size × Qty)',
                ),
              ),
              const SizedBox(height: 16),
              // Total Qty Field (calculated: base + bonus)
              TextFormField(
                controller: _totalQtyController,
                readOnly: false,
                decoration: InputDecoration(
                  labelText: 'Total Qty',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.calculate_outlined),
                  filled: true,
                  fillColor: Colors.green.shade50,
                  helperText: _selectedPackingType != null
                      ? 'Calculated: ($_selectedPackingType × Pack Size) + Bonus Qty'
                      : 'Calculated: (Qty × Pack Size) + Bonus Qty',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
              const SizedBox(height: 16),
              // Total Price Field (Editable)
              TextFormField(
                controller: _totalPriceController,
                decoration: InputDecoration(
                  labelText: 'Total Price *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.calculate),
                  prefixText: 'Rs. ',
                  filled: true,
                  fillColor: Colors.purple.shade50,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.calculate_outlined, size: 22),
                        tooltip: 'Calculator',
                        onPressed: () async {
                          final v = await _CalculatorDialog.show(
                            context,
                            initialValue: _totalPriceController.text,
                          );
                          if (v != null && mounted) {
                            _totalPriceController.text = v.toStringAsFixed(2);
                            setState(() {});
                          }
                        },
                      ),
                      if (_isManualTotalEdit)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Reset to calculated value',
                          onPressed: _resetToCalculated,
                          color: Colors.purple.shade700,
                        ),
                    ],
                  ),
                  helperText: _isManualTotalEdit
                      ? 'Manual override - tap refresh to auto-calculate'
                      : 'Price × Quantity (expense is your cost; not added to buyer total)',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                  fontSize: 16,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter total price';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Invalid price';
                  }
                  if (double.parse(value) < 0) {
                    return 'Cannot be negative';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'e.g., kg, pcs, L',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _expenseController,
                decoration: const InputDecoration(
                  labelText: 'Expense',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.money_off),
                  prefixText: 'Rs. ',
                  helperText: 'Additional expense for this item (your cost; not added to buyer total)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (value) {
                  // Trigger real-time update when expense changes
                  _onExpenseChanged();
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    _selectedDate != null
                        ? _dateFormatter.format(_selectedDate!)
                        : 'Select date',
                    style: TextStyle(
                      color: _selectedDate != null
                          ? Colors.black
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveItem,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.item == null ? 'Add' : 'Update'),
        ),
      ],
    );
  }
}
