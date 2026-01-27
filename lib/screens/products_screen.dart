import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import 'add_edit_product_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final ProductService _productService = ProductService();
  final CategoryService _categoryService = CategoryService();
  final TextEditingController _searchController = TextEditingController();
  List<Product>? _searchResults;
  String _selectedCategory = 'All';
  int _currentPage = 1;
  static const int _itemsPerPage = 12;
  
  // Average Calculator Controllers
  final TextEditingController _oldTotalItemController = TextEditingController();
  final TextEditingController _oldItemPriceController = TextEditingController();
  final TextEditingController _newTotalItemController = TextEditingController();
  final TextEditingController _newItemPriceController = TextEditingController();
  final TextEditingController _salePriceController = TextEditingController();
  
  double? _averagePrice;
  double? _totalCost;
  double? _totalItems;
  double? _profitPerItem;
  double? _totalProfit;
  bool _showAverageCalculator = false;

  @override
  void dispose() {
    _searchController.dispose();
    _oldTotalItemController.dispose();
    _oldItemPriceController.dispose();
    _newTotalItemController.dispose();
    _newItemPriceController.dispose();
    _salePriceController.dispose();
    super.dispose();
  }

  void _searchProducts(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _currentPage = 1; // Reset to first page when search is cleared
      });
      return;
    }

    final results = await _productService.searchProducts(query);
    setState(() {
      _searchResults = results;
      _currentPage = 1; // Reset to first page when searching
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');

    return Scaffold(
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchProducts('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _searchProducts,
            ),
          ),
          // Category Filter
          Container(
            height: 60,
            color: Colors.white,
            child: StreamBuilder(
              stream: _categoryService.getCategoriesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final categories = snapshot.data ?? [];
                final categoryNames = categories.map((c) => c.name).toList();
                
                // Always include 'All' as first option
                final allCategories = ['All', ...categoryNames];

                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: true,
                    dragDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: allCategories.length,
                      itemBuilder: (context, index) {
                        final category = allCategories[index];
                        final isSelected = _selectedCategory == category;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(category),
                            selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = category;
                            // Clear search when category changes
                            _searchController.clear();
                            _searchResults = null;
                            _currentPage = 1; // Reset to first page when category changes
                          });
                        },
                            selectedColor: Colors.green,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Average Calculator Section
          Container(
            color: Colors.white,
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _showAverageCalculator = !_showAverageCalculator;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calculate,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Average Calculator',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showAverageCalculator
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showAverageCalculator) ...[
                  const Divider(height: 1),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _oldTotalItemController,
                                decoration: const InputDecoration(
                                  labelText: 'Old Total Item',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.inventory_2),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _oldItemPriceController,
                                decoration: const InputDecoration(
                                  labelText: 'Old Item Price',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.attach_money),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newTotalItemController,
                                decoration: const InputDecoration(
                                  labelText: 'New Total Item',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.add_box),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _newItemPriceController,
                                decoration: const InputDecoration(
                                  labelText: 'New Item Price',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.attach_money),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _salePriceController,
                          decoration: const InputDecoration(
                            labelText: 'Sale Price (Optional - for profit scenario)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sell),
                            helperText: 'Enter sale price to calculate profit',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _calculateAveragePrice,
                          icon: const Icon(Icons.calculate),
                          label: const Text('Calculate Average Price'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        if (_averagePrice != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Calculation Results:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildResultRow('Total Items', _totalItems?.toStringAsFixed(2) ?? '0'),
                                _buildResultRow('Total Cost', formatter.format(_totalCost ?? 0)),
                                _buildResultRow(
                                  'Average Price',
                                  formatter.format(_averagePrice ?? 0),
                                  isHighlight: true,
                                ),
                                if (_salePriceController.text.isNotEmpty &&
                                    double.tryParse(_salePriceController.text) != null) ...[
                                  const Divider(height: 24),
                                  const Text(
                                    'Profit Scenario:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildResultRow(
                                    'Profit per Item',
                                    formatter.format(_profitPerItem ?? 0),
                                    color: _profitPerItem != null && _profitPerItem! > 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  _buildResultRow(
                                    'Total Profit',
                                    formatter.format(_totalProfit ?? 0),
                                    color: _totalProfit != null && _totalProfit! > 0
                                        ? Colors.green
                                        : Colors.red,
                                    isHighlight: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // Products List
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productService.getProductsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var products = _searchResults ?? snapshot.data ?? [];

                // Filter by category
                if (_selectedCategory != 'All') {
                  products = products
                      .where((p) => p.category == _selectedCategory)
                      .toList();
                }

                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty && _selectedCategory == 'All'
                              ? 'No products yet'
                              : _selectedCategory != 'All'
                                  ? 'No products in "$_selectedCategory" category'
                                  : 'No products found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedCategory != 'All'
                              ? 'Try selecting a different category or add products to this category'
                              : 'Add your first product to get started',
                        ),
                      ],
                    ),
                  );
                }

                // Calculate pagination
                final totalPages = (products.length / _itemsPerPage).ceil();
                final startIndex = (_currentPage - 1) * _itemsPerPage;
                final endIndex = (startIndex + _itemsPerPage).clamp(0, products.length);
                final paginatedProducts = products.sublist(startIndex, endIndex);

                // Reset to first page if current page is out of bounds
                if (_currentPage > totalPages && totalPages > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() {
                      _currentPage = 1;
                    });
                  });
                }

                return Column(
                  children: [
                    // Products List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: paginatedProducts.length,
                        itemBuilder: (context, index) {
                          final product = paginatedProducts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          // Optional: Navigate to product details on tap
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: Icon, Name, Price
                              Row(
                                children: [
                                  // Leading icon
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: product.stock > 10
                                          ? Colors.green.shade100
                                          : Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.shopping_bag,
                                      color: product.stock > 10 ? Colors.green[700] : Colors.red[700],
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  
                                  // Product info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${product.category}${product.formattedSize.isNotEmpty ? ' • ${product.formattedSize}' : ''}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Price
                                  Text(
                                    formatter.format(product.salePrice),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Stock info
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inventory_2,
                                      size: 16,
                                      color: Colors.grey[700],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Stock: ${product.stock.toStringAsFixed(product.stock % 1 == 0 ? 0 : 1)} ${product.unit}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              if (product.barcode != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Barcode: ${product.barcode}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                              
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              
                              // Action buttons row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: _ActionButton(
                                      icon: Icons.add_box,
                                      label: 'Add Stock',
                                      color: Colors.green,
                                      onPressed: () => _addStock(context, product),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _ActionButton(
                                      icon: Icons.edit,
                                      label: 'Edit',
                                      color: Colors.blue,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                AddEditProductScreen(product: product),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _ActionButton(
                                      icon: Icons.delete,
                                      label: 'Delete',
                                      color: Colors.red,
                                      onPressed: () => _deleteProduct(context, product),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                        },
                      ),
                    ),
                    // Pagination Controls
                    if (totalPages > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 2,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Previous Button
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _currentPage > 1
                                  ? () {
                                      setState(() {
                                        _currentPage--;
                                      });
                                    }
                                  : null,
                              tooltip: 'Previous',
                            ),
                            const SizedBox(width: 8),
                            // Page Numbers
                            ...List.generate(
                              totalPages > 7 ? 7 : totalPages,
                              (index) {
                                int pageNumber;
                                if (totalPages <= 7) {
                                  pageNumber = index + 1;
                                } else {
                                  // Show first, last, and pages around current
                                  if (_currentPage <= 4) {
                                    pageNumber = index + 1;
                                  } else if (_currentPage >= totalPages - 3) {
                                    pageNumber = totalPages - 6 + index;
                                  } else {
                                    pageNumber = _currentPage - 3 + index;
                                  }
                                }
                                
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _currentPage = pageNumber;
                                      });
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _currentPage == pageNumber
                                            ? Colors.blue
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _currentPage == pageNumber
                                              ? Colors.blue
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$pageNumber',
                                          style: TextStyle(
                                            color: _currentPage == pageNumber
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: _currentPage == pageNumber
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Next Button
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _currentPage < totalPages
                                  ? () {
                                      setState(() {
                                        _currentPage++;
                                      });
                                    }
                                  : null,
                              tooltip: 'Next',
                            ),
                          ],
                        ),
                      ),
                    // Page Info
                    if (totalPages > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        color: Colors.grey[50],
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Page $_currentPage of $totalPages',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Showing ${startIndex + 1}-${startIndex + paginatedProducts.length} of ${products.length} products',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEditProductScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }

  void _addStock(BuildContext context, Product product) {
    final TextEditingController quantityController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Stock - ${product.name}${product.formattedSize.isNotEmpty ? ' (${product.formattedSize})' : ''}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current Stock: ${product.stock.toStringAsFixed(product.stock % 1 == 0 ? 0 : 1)} ${product.unit}'),
            const SizedBox(height: 16),
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(
                labelText: 'Quantity to Add',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.add),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final quantity = double.tryParse(quantityController.text) ?? 0;
              if (quantity <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter valid quantity')),
                );
                return;
              }

              await _productService.updateStock(product.id, quantity);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added $quantity ${product.unit} to stock')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _deleteProduct(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _productService.deleteProduct(product.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Product deleted')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _calculateAveragePrice() {
    final oldTotalItem = double.tryParse(_oldTotalItemController.text) ?? 0;
    final oldItemPrice = double.tryParse(_oldItemPriceController.text) ?? 0;
    final newTotalItem = double.tryParse(_newTotalItemController.text) ?? 0;
    final newItemPrice = double.tryParse(_newItemPriceController.text) ?? 0;
    final salePrice = double.tryParse(_salePriceController.text);

    if (oldTotalItem <= 0 || oldItemPrice <= 0 || newTotalItem <= 0 || newItemPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid values for all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Calculate total cost
    final oldTotalCost = oldTotalItem * oldItemPrice;
    final newTotalCost = newTotalItem * newItemPrice;
    final totalCost = oldTotalCost + newTotalCost;

    // Calculate total items
    final totalItems = oldTotalItem + newTotalItem;

    // Calculate average price
    final averagePrice = totalCost / totalItems;

    // Calculate profit scenario if sale price is provided
    double? profitPerItem;
    double? totalProfit;
    if (salePrice != null && salePrice > 0) {
      profitPerItem = salePrice - averagePrice;
      totalProfit = profitPerItem * totalItems;
    }

    setState(() {
      _averagePrice = averagePrice;
      _totalCost = totalCost;
      _totalItems = totalItems;
      _profitPerItem = profitPerItem;
      _totalProfit = totalProfit;
    });
  }

  Widget _buildResultRow(String label, String value, {bool isHighlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlight ? 18 : 14,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: color ?? (isHighlight ? Colors.green[700] : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.3), width: 1),
        ),
      ),
    );
  }
}