import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/seller_order.dart';
import '../models/seller.dart';
import '../services/sales_service.dart';
import '../services/product_service.dart';
import '../services/seller_order_service.dart';
import '../services/seller_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final SalesService _salesService = SalesService();
  final SellerOrderService _sellerOrderService = SellerOrderService();
  final SellerService _sellerService = SellerService();
  final TextEditingController _searchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _filterByDate = false;
  String _transactionTypeFilter = 'all'; // 'all', 'pos', 'wholesale'
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                hintText: 'Search by seller name, description, customer, or sale ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),
          // Filter Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Transaction Type Filter
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'pos', label: Text('POS')),
                    ButtonSegment(value: 'wholesale', label: Text('Wholesale')),
                  ],
                  selected: {_transactionTypeFilter},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _transactionTypeFilter = newSelection.first;
                    });
                  },
                  style: ButtonStyle(
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                // Date Filter
                IconButton(
                  icon: Icon(_filterByDate ? Icons.filter_alt : Icons.filter_alt_outlined),
                  onPressed: _showDateFilter,
                ),
              ],
            ),
          ),
          // Sales List
          Expanded(
            child: Column(
              children: [
                if (_filterByDate && _startDate != null && _endDate != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.blue.shade50,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Showing: ${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _filterByDate = false;
                              _startDate = null;
                              _endDate = null;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<Sale>>(
                    stream: _filterByDate && _startDate != null && _endDate != null
                        ? _salesService.getSalesByDateRange(_startDate!, _endDate!)
                        : _salesService.getSalesStream(),
                    builder: (context, salesSnapshot) {
                      return StreamBuilder<List<SellerOrder>>(
                        stream: _sellerOrderService.getAllOrders(),
                        builder: (context, ordersSnapshot) {
                          if (salesSnapshot.connectionState == ConnectionState.waiting ||
                              ordersSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (salesSnapshot.hasError) {
                            return Center(child: Text('Error: ${salesSnapshot.error}'));
                          }

                          if (ordersSnapshot.hasError) {
                            return Center(child: Text('Error: ${ordersSnapshot.error}'));
                          }

                          var sales = salesSnapshot.data ?? [];
                          var orders = ordersSnapshot.data ?? [];

                          // Filter orders by date if needed
                          if (_filterByDate && _startDate != null && _endDate != null) {
                            orders = orders.where((order) {
                              final orderDate = order.completedAt ?? order.createdAt;
                              return orderDate.isAfter(_startDate!.subtract(const Duration(seconds: 1))) &&
                                     orderDate.isBefore(_endDate!.add(const Duration(days: 1)));
                            }).toList();
                          }

                          // Filter by transaction type
                          if (_transactionTypeFilter == 'pos') {
                            orders = [];
                          } else if (_transactionTypeFilter == 'wholesale') {
                            sales = [];
                          }

                          // Apply search filter (seller name will be filtered in the widget builder)
                          final searchQuery = _searchController.text.toLowerCase().trim();
                          if (searchQuery.isNotEmpty) {
                            // First filter by fields we can check directly
                            sales = sales.where((sale) {
                              // Search in description
                              if (sale.description != null && 
                                  sale.description!.toLowerCase().contains(searchQuery)) {
                                return true;
                              }
                              // Search in customer name
                              if (sale.customerName != null && 
                                  sale.customerName!.toLowerCase().contains(searchQuery)) {
                                return true;
                              }
                              // Search in sale ID
                              if (sale.id.toLowerCase().contains(searchQuery)) {
                                return true;
                              }
                              // Search in item names
                              if (sale.items.any((item) => 
                                  item.productName.toLowerCase().contains(searchQuery))) {
                                return true;
                              }
                              // If sale has sellerId, include it (seller name will be checked in builder)
                              // If no sellerId and no other match, exclude it
                              return sale.sellerId != null;
                            }).toList();
                          }

                          // Create combined list
                          final combinedTransactions = <Map<String, dynamic>>[];
                          
                          // Add sales
                          for (var sale in sales) {
                            combinedTransactions.add({
                              'type': 'pos',
                              'date': sale.createdAt,
                              'data': sale,
                            });
                          }

                          // Add completed wholesale orders
                          for (var order in orders.where((o) => o.status == OrderStatus.completed)) {
                            combinedTransactions.add({
                              'type': 'wholesale',
                              'date': order.completedAt ?? order.createdAt,
                              'data': order,
                            });
                          }

                          // Sort by date (newest first)
                          combinedTransactions.sort((a, b) => 
                            (b['date'] as DateTime).compareTo(a['date'] as DateTime)
                          );

                          // Filter by search query for seller names (async)
                          if (searchQuery.isNotEmpty) {
                            // We'll filter seller names in the widget builder
                          }

                          if (combinedTransactions.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No transactions yet',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Sales and orders will appear here',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: combinedTransactions.length,
                            itemBuilder: (context, index) {
                              final transaction = combinedTransactions[index];
                              
                              if (transaction['type'] == 'pos') {
                                final sale = transaction['data'] as Sale;
                                // Check if search query matches seller name
                                if (searchQuery.isNotEmpty && sale.sellerId != null) {
                                  return FutureBuilder<Seller?>(
                                    future: _sellerService.getSellerById(sale.sellerId!),
                                    builder: (context, sellerSnapshot) {
                                      if (sellerSnapshot.hasData && sellerSnapshot.data != null) {
                                        final seller = sellerSnapshot.data!;
                                        if (!seller.name.toLowerCase().contains(searchQuery)) {
                                          return const SizedBox.shrink();
                                        }
                                      }
                                      return _SaleCard(
                                        sale: sale,
                                        onReturn: () => _showReturnDialog(context, sale),
                                      );
                                    },
                                  );
                                }
                                return _SaleCard(
                                  sale: sale,
                                  onReturn: () => _showReturnDialog(context, sale),
                                );
                              } else {
                                final order = transaction['data'] as SellerOrder;
                                return _WholesaleOrderCard(order: order);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReturnDialog(BuildContext context, Sale sale) {
    // Check if there are any items that can be returned
    final returnableItems = sale.items.where((item) => item.remainingQuantity > 0).toList();
    
    if (returnableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All items have already been returned')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SaleReturnScreen(sale: sale),
      ),
    );
  }

  void _showDateFilter() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Date'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Today'),
              onTap: () {
                final now = DateTime.now();
                setState(() {
                  _filterByDate = true;
                  _startDate = DateTime(now.year, now.month, now.day);
                  _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Last 7 Days'),
              onTap: () {
                final now = DateTime.now();
                setState(() {
                  _filterByDate = true;
                  _startDate = now.subtract(const Duration(days: 7));
                  _endDate = now;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Last 30 Days'),
              onTap: () {
                final now = DateTime.now();
                setState(() {
                  _filterByDate = true;
                  _startDate = now.subtract(const Duration(days: 30));
                  _endDate = now;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Custom Range'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  ),
                );
                if (picked != null) {
                  setState(() {
                    _filterByDate = true;
                    _startDate = picked.start;
                    _endDate = picked.end;
                  });
                }
              },
            ),
            const Divider(),
            ListTile(
              title: const Text('Show All'),
              onTap: () {
                setState(() {
                  _filterByDate = false;
                  _startDate = null;
                  _endDate = null;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final Sale sale;
  final VoidCallback onReturn;

  const _SaleCard({
    required this.sale,
    required this.onReturn,
  });

  Future<Seller?> _getSeller(String? sellerId) async {
    if (sellerId == null) return null;
    final sellerService = SellerService();
    return await sellerService.getSellerById(sellerId);
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy hh:mm a');

    final hasReturns = sale.returnedAmount > 0;
    final canReturn = sale.items.any((item) => item.remainingQuantity > 0);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: hasReturns ? Colors.orange.shade100 : Colors.green.shade100,
          child: Icon(
            hasReturns ? Icons.assignment_return : Icons.receipt, 
            color: hasReturns ? Colors.orange.shade700 : Colors.green.shade700,
          ),
        ),
        title: Row(
          children: [
            Text(
              formatter.format(sale.total),
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 18,
                decoration: hasReturns ? TextDecoration.lineThrough : null,
              ),
            ),
            if (hasReturns) ...[
              const SizedBox(width: 8),
              Text(
                formatter.format(sale.netTotal),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateFormatter.format(sale.createdAt)),
            Row(
              children: [
                if (sale.isBorrowPayment)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          'Borrow',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (sale.saleType == 'wholesale')
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Wholesale',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text('${sale.items.length} item(s) • ${sale.paymentMethod}'),
              ],
            ),
            if (sale.sellerId != null)
              FutureBuilder<Seller?>(
                future: _getSeller(sale.sellerId),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final seller = snapshot.data!;
                    return Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.blue[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Seller: ${seller.name}',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            if (sale.customerName != null && sale.customerName!.isNotEmpty)
              Text(
                sale.customerName!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            if (sale.description != null && sale.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.description, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sale.description!,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (hasReturns)
              Text(
                'Returned: ${formatter.format(sale.returnedAmount)}',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            if (sale.netProfit > 0 && !sale.isBorrowPayment)
              Text(
                'Profit: ${formatter.format(sale.netProfit)}',
                style: TextStyle(
                  color: Colors.teal.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            if (sale.isBorrowPayment)
              Text(
                'Borrow Payment - No Profit',
                style: TextStyle(
                  color: Colors.amber.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        trailing: canReturn 
            ? IconButton(
                icon: const Icon(Icons.assignment_return, color: Colors.orange),
                onPressed: onReturn,
                tooltip: 'Return Items',
              )
            : null,
        children: [
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Items:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...sale.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.productName} x${item.quantity}'),
                              if (item.returnedQuantity > 0)
                                Text(
                                  'Returned: ${item.returnedQuantity}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          formatter.format(item.subtotal),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:'),
                    Text(
                      formatter.format(sale.total),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        decoration: hasReturns ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
                if (hasReturns) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Returned:'),
                      Text(
                        '- ${formatter.format(sale.returnedAmount)}',
                        style: TextStyle(
                          color: Colors.orange.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Total:'),
                      Text(
                        formatter.format(sale.netTotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
                if (sale.netProfit > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Net Profit:'),
                      Text(
                        formatter.format(sale.netProfit),
                        style: TextStyle(
                          color: Colors.teal.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Paid:'),
                    Text(formatter.format(sale.amountPaid)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Change:'),
                    Text(
                      formatter.format(sale.change),
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
                if (sale.description != null && sale.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.description, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Description:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sale.description!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[800],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (sale.sellerId != null)
                  FutureBuilder<Seller?>(
                    future: _getSeller(sale.sellerId),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        final seller = snapshot.data!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 16, color: Colors.blue[600]),
                              const SizedBox(width: 8),
                              Text(
                                'Seller: ${seller.name}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                const SizedBox(height: 8),
                Text(
                  'ID: ${sale.id}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Sale Return Screen
class SaleReturnScreen extends StatefulWidget {
  final Sale sale;

  const SaleReturnScreen({super.key, required this.sale});

  @override
  State<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends State<SaleReturnScreen> {
  final SalesService _salesService = SalesService();
  final ProductService _productService = ProductService();
  final Map<String, double> _returnQuantities = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Initialize return quantities to 0
    for (var item in widget.sale.items) {
      if (item.remainingQuantity > 0) {
        _returnQuantities[item.productId] = 0.0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final returnableItems = widget.sale.items
        .where((item) => item.remainingQuantity > 0)
        .toList();

    double totalReturnAmount = 0;
    for (var item in returnableItems) {
      final returnQty = _returnQuantities[item.productId] ?? 0.0;
      totalReturnAmount += item.price * returnQty;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Return Items'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Return info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sale ID: ${widget.sale.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Original Total: ${formatter.format(widget.sale.total)}'),
                if (widget.sale.returnedAmount > 0)
                  Text(
                    'Previously Returned: ${formatter.format(widget.sale.returnedAmount)}',
                    style: TextStyle(color: Colors.orange.shade700),
                  ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: returnableItems.length,
              itemBuilder: (context, index) {
                final item = returnableItems[index];
                final returnQty = _returnQuantities[item.productId] ?? 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Price: ${formatter.format(item.price)} each'),
                        Text('Available to return: ${item.remainingQuantity}'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Return Quantity:'),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: returnQty > 0
                                  ? () {
                                      setState(() {
                                        // Support fractional quantities for weight-based items
                                        final decrement = returnQty % 1 == 0 ? 1.0 : 0.1;
                                        _returnQuantities[item.productId] = (returnQty - decrement).clamp(0.0, item.remainingQuantity);
                                      });
                                    }
                                  : null,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                returnQty.toStringAsFixed(returnQty % 1 == 0 ? 0 : 1),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: returnQty < item.remainingQuantity
                                  ? () {
                                      setState(() {
                                        // Support fractional quantities for weight-based items
                                        final increment = returnQty % 1 == 0 ? 1.0 : 0.1;
                                        _returnQuantities[item.productId] = (returnQty + increment).clamp(0.0, item.remainingQuantity);
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        if (returnQty > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Refund: ${formatter.format(item.price * returnQty)}',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Refund:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatter.format(totalReturnAmount),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: totalReturnAmount > 0 && !_isProcessing
                        ? _processReturn
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Process Return',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processReturn() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Calculate total return amount
      double totalReturnAmount = 0;
      final updatedItems = <SaleItem>[];
      final stockUpdates = <String, double>{}; // Track stock updates

      // First, prepare all updates
      for (var item in widget.sale.items) {
        final returnQty = _returnQuantities[item.productId] ?? 0.0;
        final newReturnedQty = item.returnedQuantity + returnQty;

        totalReturnAmount += item.price * returnQty;

        // Create updated sale item
        updatedItems.add(SaleItem(
          productId: item.productId,
          productName: item.productName,
          price: item.price,
          quantity: item.quantity,
          subtotal: item.subtotal,
          returnedQuantity: newReturnedQty,
        ));

        // Track stock updates (accumulate if same product appears multiple times)
        if (returnQty > 0) {
          stockUpdates[item.productId] = (stockUpdates[item.productId] ?? 0.0) + returnQty;
        }
      }

      // Update stock for each returned item
      for (var entry in stockUpdates.entries) {
        try {
          print('Updating stock for product ${entry.key}: adding ${entry.value} units');
          await _productService.updateStock(entry.key, entry.value);
          print('Stock updated successfully for product ${entry.key}');
        } catch (e) {
          print('Error updating stock for product ${entry.key}: $e');
          throw Exception('Failed to restore stock for product ${entry.key}');
        }
      }

      // Store previous returned amount before update
      final previousReturnedAmount = widget.sale.returnedAmount;
      
      // Create updated sale - IMPORTANT: Preserve all original sale fields including creditUsed and recoveryBalance
      final updatedSale = Sale(
        id: widget.sale.id,
        items: updatedItems,
        total: widget.sale.total,
        profit: widget.sale.profit,
        amountPaid: widget.sale.amountPaid,
        change: widget.sale.change,
        createdAt: widget.sale.createdAt,
        customerName: widget.sale.customerName,
        paymentMethod: widget.sale.paymentMethod,
        returnedAmount: widget.sale.returnedAmount + totalReturnAmount,
        isPartialReturn: true,
        sellerId: widget.sale.sellerId, // Preserve sellerId for return processing
        recoveryBalance: widget.sale.recoveryBalance, // Preserve recovery balance
        creditUsed: widget.sale.creditUsed, // Preserve original credit used (critical for proportional credit restoration)
        isBorrowPayment: widget.sale.isBorrowPayment, // Preserve borrow payment flag
        saleType: widget.sale.saleType, // Preserve sale type
        description: widget.sale.description, // Preserve description
      );

      // Update sale in database and update seller history if needed
      await _salesService.processSaleReturn(updatedSale, previousReturnedAmount: previousReturnedAmount);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Return processed: ${NumberFormat.currency(symbol: 'Rs. ').format(totalReturnAmount)} refunded\n'
              'Stock restored for ${stockUpdates.length} product(s)',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error in _processReturn: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing return: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}

// Wholesale Order Card Widget
class _WholesaleOrderCard extends StatelessWidget {
  final SellerOrder order;

  const _WholesaleOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy hh:mm a');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.business, color: Colors.blue.shade700),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'WHOLESALE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.sellerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.sellerPhone,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatter.format(order.total),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.green,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.sellerLocation,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                dateFormatter.format(order.completedAt ?? order.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          // Order Items
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              return ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.shopping_bag, size: 20, color: Colors.blue.shade700),
                ),
                title: Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Qty: ${item.quantity.toInt()} × ${formatter.format(item.wholesalePrice)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatter.format(item.subtotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Profit: ${formatter.format(item.profit)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          // Summary
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Items:',
                      style: TextStyle(fontSize: 14),
                    ),
                    Text(
                      '${order.items.length} items',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatter.format(order.total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Profit:',
                      style: TextStyle(fontSize: 14, color: Colors.blue),
                    ),
                    Text(
                      formatter.format(order.profit),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

