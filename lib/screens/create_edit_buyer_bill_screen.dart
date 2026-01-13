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
  final _formKey = GlobalKey<FormState>();
  final List<BuyerBillItem> _items = [];
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');
  
  String _paymentMethod = 'cash';
  String? _notes;
  double _amountPaid = 0.0;
  bool _isLoading = false;
  late TextEditingController _billNumberController;

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
    } else {
      // Auto-generate bill number for new bills
      _billNumberController = TextEditingController(
        text: _generateBillNumber(),
      );
    }
  }

  @override
  void dispose() {
    _billNumberController.dispose();
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
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
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
      final bill = BuyerBill(
        id: widget.bill?.id ?? const Uuid().v4(),
        buyerId: widget.buyer.id,
        buyerName: widget.buyer.name,
        items: _items,
        total: _total,
        totalExpense: _totalExpense,
        finalPrice: _finalPrice,
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
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Final Price:',
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
  DateTime? _selectedDate;
  final DateFormat _dateFormatter = DateFormat('MMM dd, yyyy');
  bool _isManualTotalEdit = false;
  String? _selectedCategory;
  Product? _selectedProduct;
  double? _currentProductStock; // Track current stock for real-time updates

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
    _selectedDate = widget.item?.date ?? DateTime.now();
    
    // Initialize total price controller (including expense)
    final initialPrice = double.tryParse(_priceController.text) ?? 0.0;
    final initialQuantity = double.tryParse(_quantityController.text) ?? 0.0;
    final initialExpense = double.tryParse(_expenseController.text) ?? 0.0;
    final initialTotal = (initialPrice * initialQuantity) + initialExpense;
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
    
    // Load product stock if editing existing item
    if (widget.item != null && _nameController.text.isNotEmpty) {
      _loadProductStockByName(_nameController.text);
    }
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
  
  void _onPriceOrQuantityChanged() {
    // Only auto-calculate total if user hasn't manually edited it recently
    if (!_isManualTotalEdit) {
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final quantity = double.tryParse(_quantityController.text) ?? 0.0;
      final expense = double.tryParse(_expenseController.text) ?? 0.0;
      final calculatedTotal = (price * quantity) + expense;
      
      // Temporarily remove listeners to avoid recursive updates
      _totalPriceController.removeListener(_onTotalPriceChanged);
      _totalPriceController.text = calculatedTotal > 0 ? calculatedTotal.toStringAsFixed(2) : '';
      _totalPriceController.addListener(_onTotalPriceChanged);
    }
    
    // Update stock info when quantity changes
    _updateStockInfo();
  }

  void _onExpenseChanged() {
    // Update total price in real-time when expense changes
    if (!_isManualTotalEdit && mounted) {
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final quantity = double.tryParse(_quantityController.text) ?? 0.0;
      final expense = double.tryParse(_expenseController.text) ?? 0.0;
      final calculatedTotal = (price * quantity) + expense;
      
      // Temporarily remove listener to avoid recursive updates
      _totalPriceController.removeListener(_onTotalPriceChanged);
      _totalPriceController.text = calculatedTotal > 0 ? calculatedTotal.toStringAsFixed(2) : '';
      _totalPriceController.addListener(_onTotalPriceChanged);
      
      // Force UI update
      setState(() {});
    }
  }
  
  void _onTotalPriceChanged() {
    // When total price is manually changed, recalculate the price field
    // Note: Total price includes expense, so we need to subtract it
    final totalPriceWithExpense = double.tryParse(_totalPriceController.text) ?? 0.0;
    final quantity = double.tryParse(_quantityController.text) ?? 1.0;
    final expense = double.tryParse(_expenseController.text) ?? 0.0;
    
    if (totalPriceWithExpense > 0 && quantity > 0) {
      _isManualTotalEdit = true;
      // Extract base total price (without expense) and calculate price per unit
      final baseTotalPrice = totalPriceWithExpense - expense;
      final newPrice = baseTotalPrice / quantity;
      
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

  @override
  void dispose() {
    _priceController.removeListener(_onPriceOrQuantityChanged);
    _quantityController.removeListener(_onPriceOrQuantityChanged);
    _totalPriceController.removeListener(_onTotalPriceChanged);
    _expenseController.removeListener(_onExpenseChanged);
    _productSearchController.removeListener(_onProductSearchChanged);
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _expenseController.dispose();
    _totalPriceController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final price = double.parse(_priceController.text);
      final quantity = double.parse(_quantityController.text);
      final unit = _unitController.text.trim().isEmpty
          ? 'pcs'
          : _unitController.text.trim();
      final expense = double.tryParse(_expenseController.text) ?? 0.0;
      
      // Total price from controller now includes expense when auto-calculated
      // If manually edited, we need to check if user included expense or not
      // For auto-calculated: totalPrice = (price × quantity) + expense
      // For manual edit: we assume user entered base totalPrice (without expense)
      final totalPriceFromController = double.parse(_totalPriceController.text);
      final baseTotalPrice = _isManualTotalEdit 
          ? totalPriceFromController  // Manual edit: assume base price
          : totalPriceFromController - expense; // Auto-calculated: subtract expense to get base
      final subtotal = baseTotalPrice + expense; // Subtotal = base + expense

      // Update or create product stock and purchase price
      // For buyer bills, we INCREASE stock (buying from buyer adds to inventory)
      // Also calculate weighted average purchase price
      Product? productToUpdate;
      
      // Check if product exists (by name and category if category is selected)
      if (_selectedProduct != null) {
        // Product was selected from list - use it
        productToUpdate = await _productService.getProductById(_selectedProduct!.id);
      } else if (name.isNotEmpty && _selectedCategory != null) {
        // Product not found but name and category provided - search for existing product
        try {
          final allProducts = await _productService.searchProducts(name);
          productToUpdate = allProducts.firstWhere(
            (p) => p.name.toLowerCase() == name.toLowerCase() && 
                   p.category.toLowerCase() == _selectedCategory!.toLowerCase(),
          );
        } catch (e) {
          // Product doesn't exist - will be created below
          productToUpdate = null;
        }
      }
      
      // If product exists, update it; otherwise create new one
      if (productToUpdate != null) {
        try {
          final currentProduct = productToUpdate;
          
          // Check if we're editing an existing item
          if (widget.item != null) {
            // If editing, we need to adjust stock and recalculate average price
            final oldQuantity = widget.item!.quantity;
            final oldPrice = widget.item!.price;
            final oldExpense = widget.item!.expense;
            final quantityDifference = quantity - oldQuantity;
            
            // Update if quantity, price, or expense changed
            if (quantityDifference != 0 || oldPrice != price || oldExpense != expense) {
              // Reverse the old transaction to get the state before it
              // Current stock includes the old quantity, so subtract it
              final stockBeforeOldTransaction = currentProduct.stock - oldQuantity;
              
              // Reverse the average calculation to get the total value before old transaction
              // Note: Old expense may not have been included in purchase price (for backward compatibility)
              // So we reverse: oldQuantity * oldPrice (without old expense)
              // If old expense was included, this will slightly over-correct, but that's acceptable
              final totalValueBeforeOldTransaction = (currentProduct.stock * currentProduct.purchasePrice) - (oldQuantity * oldPrice);
              
              // Now add the new transaction (including expense)
              final newTotalValue = totalValueBeforeOldTransaction + (quantity * price) + expense;
              final newTotalStock = stockBeforeOldTransaction + quantity;
              
              // Calculate weighted average
              final averagePurchasePrice = newTotalStock > 0 
                  ? newTotalValue / newTotalStock 
                  : price;
              
              // Update stock and purchase price
              final updatedProduct = currentProduct.copyWith(
                stock: newTotalStock,
                purchasePrice: averagePurchasePrice,
                updatedAt: DateTime.now(),
              );
              
              await _productService.updateProduct(updatedProduct);
            }
          } else {
            // New item - calculate weighted average purchase price
            final oldStock = currentProduct.stock;
            final oldPrice = currentProduct.purchasePrice;
            final newQuantity = quantity;
            final newPrice = price;
            
            // Calculate weighted average: (Old Stock × Old Price + New Quantity × New Price + Expense) / (Old Stock + New Quantity)
            // Expense is included as part of the total cost of acquiring the items
            final oldTotalValue = oldStock * oldPrice;
            final newTotalValue = (newQuantity * newPrice) + expense;
            final totalValue = oldTotalValue + newTotalValue;
            final totalStock = oldStock + newQuantity;
            
            final averagePurchasePrice = totalStock > 0 
                ? totalValue / totalStock 
                : newPrice;
            
            // Update stock and purchase price
            final updatedProduct = currentProduct.copyWith(
              stock: totalStock,
              purchasePrice: averagePurchasePrice,
              updatedAt: DateTime.now(),
            );
            
            await _productService.updateProduct(updatedProduct);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error updating stock: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else if (name.isNotEmpty && _selectedCategory != null) {
        // Product doesn't exist - create new one
        try {
          final newProduct = Product(
            id: const Uuid().v4(),
            name: name,
            purchasePrice: price,
            salePrice: price * 1.1, // Default 10% markup, can be edited later
            stock: quantity,
            unit: unit,
            category: _selectedCategory!,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await _productService.addProduct(newProduct);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('New product "$name" created in $_selectedCategory category'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error creating product: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      final item = BuyerBillItem(
        id: widget.item?.id ?? const Uuid().v4(),
        itemName: name,
        price: price,
        unit: unit,
        quantity: quantity,
        expense: expense,
        subtotal: subtotal,
        date: _selectedDate,
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
                                  final totalStock = _currentProductStock! + enteredQty;
                                  
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
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Price *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.currency_rupee),
                        prefixText: 'Rs. ',
                        helperText: 'Purchase price',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (value) {
                        setState(() {}); // Trigger rebuild for real-time average price calculation
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
                        labelText: 'Qty *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.numbers),
                        helperText: 'Quantity to add to stock',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (value) {
                        setState(() {}); // Trigger rebuild for real-time stock display
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
                  suffixIcon: _isManualTotalEdit
                      ? IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          tooltip: 'Reset to calculated value',
                          onPressed: _resetToCalculated,
                          color: Colors.purple.shade700,
                        )
                      : null,
                  helperText: _isManualTotalEdit
                      ? 'Manual override - tap refresh to auto-calculate'
                      : 'Auto-calculated (Price × Quantity + Expense)',
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
                  helperText: 'Additional expense for this item (updates total price in real-time)',
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
