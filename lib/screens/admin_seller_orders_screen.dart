import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/seller_order.dart';
import '../services/seller_order_service.dart';

class AdminSellerOrdersScreen extends StatefulWidget {
  const AdminSellerOrdersScreen({super.key});

  @override
  State<AdminSellerOrdersScreen> createState() => _AdminSellerOrdersScreenState();
}

class _AdminSellerOrdersScreenState extends State<AdminSellerOrdersScreen> {
  final _orderService = SellerOrderService();
  OrderStatus? _filterStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seller App Orders'),
        actions: [
          // Filter dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButton<OrderStatus?>(
              value: _filterStatus,
              hint: const Text('All Orders'),
              underline: Container(),
              dropdownColor: Colors.white,
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Orders'),
                ),
                ...OrderStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(status.name.toUpperCase()),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() => _filterStatus = value);
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<SellerOrder>>(
        stream: _orderService.getAllOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          var orders = snapshot.data ?? [];

          // Apply filter
          if (_filterStatus != null) {
            orders = orders.where((o) => o.status == _filterStatus).toList();
          }

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 100, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    _filterStatus == null
                        ? 'No orders yet'
                        : 'No ${_filterStatus!.name} orders',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Orders from seller app will appear here',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Stats Summary
              _buildStatsSummary(orders),
              const Divider(height: 1),
              
              // Orders List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    return _OrderCard(order: orders[index]);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsSummary(List<SellerOrder> orders) {
    final pending = orders.where((o) => o.status == OrderStatus.pending).length;
    final confirmed = orders.where((o) => o.status == OrderStatus.confirmed).length;
    final completed = orders.where((o) => o.status == OrderStatus.completed).length;
    final cancelled = orders.where((o) => o.status == OrderStatus.cancelled).length;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCard('Pending', pending, Colors.orange),
          _StatCard('Confirmed', confirmed, Colors.blue),
          _StatCard('Completed', completed, Colors.green),
          _StatCard('Cancelled', cancelled, Colors.red),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatCard(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatefulWidget {
  final SellerOrder order;

  const _OrderCard({required this.order});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late List<TextEditingController> _qtyControllers;
  late List<TextEditingController> _priceControllers;
  final _orderService = SellerOrderService();

  SellerOrder get order => widget.order;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _qtyControllers = order.items
        .map((e) => TextEditingController(text: e.quantity.toStringAsFixed(0)))
        .toList();
    _priceControllers = order.items
        .map((e) => TextEditingController(text: e.wholesalePrice.toStringAsFixed(2)))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) c.dispose();
    for (final c in _priceControllers) c.dispose();
    super.dispose();
  }

  List<OrderItem> _getCurrentItems() {
    final list = <OrderItem>[];
    for (int i = 0; i < order.items.length; i++) {
      final orig = order.items[i];
      final qty = double.tryParse(_qtyControllers[i].text) ?? orig.quantity;
      final price = double.tryParse(_priceControllers[i].text) ?? orig.wholesalePrice;
      list.add(OrderItem(
        productId: orig.productId,
        productName: orig.productName,
        wholesalePrice: price,
        quantity: qty,
        subtotal: qty * price,
        purchasePrice: orig.purchasePrice,
      ));
    }
    return list;
  }

  double _getCurrentTotal() =>
      _getCurrentItems().fold(0, (s, e) => s + e.subtotal);

  double _getCurrentProfit() =>
      _getCurrentItems().fold(0, (s, e) => s + (e.wholesalePrice - e.purchasePrice) * e.quantity);

  bool get _isEditable =>
      order.status == OrderStatus.pending || order.status == OrderStatus.confirmed;

  Color _getStatusColor() {
    switch (order.status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.completed:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (order.status) {
      case OrderStatus.pending:
        return Icons.access_time;
      case OrderStatus.confirmed:
        return Icons.check_circle_outline;
      case OrderStatus.completed:
        return Icons.check_circle;
      case OrderStatus.cancelled:
        return Icons.cancel;
    }
  }

  String _getStatusText() {
    switch (order.status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: 'Rs. ');
    final dateFormatter = DateFormat('MMM dd, yyyy hh:mm a');
    final displayTotal = _isEditable ? _getCurrentTotal() : order.total;
    final displayProfit = _isEditable ? _getCurrentProfit() : order.profit;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(),
          child: Icon(_getStatusIcon(), color: Colors.white, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.sellerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatter.format(displayTotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(order.sellerLocation),
              ],
            ),
            Text(
              dateFormatter.format(order.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (order.cancelReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Reason: ${order.cancelReason}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        children: [
          const Divider(height: 1),
          // Order Items (editable when pending/confirmed)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              if (_isEditable) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shopping_bag, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(item.productName,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 56,
                        child: TextField(
                          controller: _qtyControllers[index],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _priceControllers[index],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatter.format(
                                (double.tryParse(_qtyControllers[index].text) ?? item.quantity) *
                                    (double.tryParse(_priceControllers[index].text) ?? item.wholesalePrice)),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Profit: ${formatter.format(((double.tryParse(_priceControllers[index].text) ?? item.wholesalePrice) - item.purchasePrice) * (double.tryParse(_qtyControllers[index].text) ?? item.quantity))}',
                            style: TextStyle(fontSize: 11, color: Colors.green[700]),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
              return ListTile(
                leading: const Icon(Icons.shopping_bag, color: Colors.green),
                title: Text(item.productName),
                subtitle: Text(
                  'Qty: ${item.quantity.toInt()} × ${formatter.format(item.wholesalePrice)}',
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
          // Summary and Actions
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
                      '${order.items.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      formatter.format(displayTotal),
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
                      'Expected Profit:',
                      style: TextStyle(fontSize: 14, color: Colors.blue),
                    ),
                    Text(
                      formatter.format(displayProfit),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                if (_isEditable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Edit qty/price above; changes save when you Confirm or Complete.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                const SizedBox(height: 16),
                _buildActionButtons(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (order.status == OrderStatus.pending) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmOrder(context),
              icon: const Icon(Icons.check_circle),
              label: const Text('Confirm Order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _cancelOrder(context),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      );
    } else if (order.status == OrderStatus.confirmed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _completeOrder(context),
          icon: const Icon(Icons.done_all),
          label: const Text('Complete Order'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Future<void> _confirmOrder(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Order'),
        content: const Text(
          'Save any edits and confirm this order? The seller app will update in real time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    final res = await _orderService.updateOrderDetails(order.id, _getCurrentItems());
    if (!context.mounted) return;
    if (!res['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']), backgroundColor: Colors.red),
      );
      return;
    }

    final result = await _orderService.confirmOrder(order.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _completeOrder(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Order'),
        content: const Text(
          'Save any edits, then this will:\n• Update product stock\n• Add profit to dashboard\n\nThe seller app will see the final amounts in real time.\n\nComplete this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    final res = await _orderService.updateOrderDetails(order.id, _getCurrentItems());
    if (!context.mounted) return;
    if (!res['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']), backgroundColor: Colors.red),
      );
      return;
    }

    final result = await _orderService.completeOrder(order.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['success'] ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelOrder(BuildContext context) async {
    final reasonController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to cancel this order?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final reason = reasonController.text.trim().isEmpty
          ? 'Cancelled by admin'
          : reasonController.text.trim();

      final result = await _orderService.adminCancelOrder(order.id, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: result['success'] ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}
