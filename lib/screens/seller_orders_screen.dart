import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/seller.dart';
import '../models/seller_order.dart';
import '../models/product.dart';
import '../providers/seller_cart_provider.dart';
import '../services/seller_order_service.dart';
import '../services/product_service.dart';
import 'seller_cart_screen.dart';

class SellerOrdersScreen extends StatelessWidget {
  final Seller seller;

  const SellerOrdersScreen({super.key, required this.seller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
      ),
      body: StreamBuilder<List<SellerOrder>>(
        stream: SellerOrderService().getSellerOrders(seller.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final orders = snapshot.data ?? [];

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 100, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    'No orders yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your orders will appear here',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              return _OrderCard(
                order: orders[index],
                seller: seller,
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final SellerOrder order;
  final Seller seller;

  const _OrderCard({required this.order, required this.seller});

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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(),
          child: Icon(_getStatusIcon(), color: Colors.white),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                formatter.format(order.total),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getStatusText(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(dateFormatter.format(order.createdAt)),
            Text('${order.items.length} item(s)'),
            if (order.cancelReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Reason: ${order.cancelReason}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
        children: [
          const Divider(height: 1),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              return ListTile(
                leading: const Icon(Icons.shopping_bag, color: Colors.green),
                title: Text(item.productName),
                subtitle: Text('Qty: ${item.quantity.toInt()} × ${formatter.format(item.wholesalePrice)}'),
                trailing: Text(
                  formatter.format(item.subtotal),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                if (order.status == OrderStatus.pending) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _editOrder(context),
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showCancelDialog(context),
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel Order'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editOrder(BuildContext context) async {
    final productService = ProductService();
    final products = <Product>[];
    for (final item in order.items) {
      final p = await productService.getProductById(item.productId);
      if (p != null) products.add(p);
    }
    if (!context.mounted) return;
    if (products.length < order.items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some products are no longer available and were skipped.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    context.read<SellerCartProvider>().loadOrderForEdit(order, products);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SellerCartScreen(seller: seller),
      ),
    );
  }

  void _showCancelDialog(BuildContext context) {
    final reasonController = TextEditingController();

    showDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim().isEmpty
                  ? 'Cancelled by seller'
                  : reasonController.text.trim();

              Navigator.pop(context);

              final result = await SellerOrderService().cancelOrder(
                order.id,
                reason,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result['message']),
                    backgroundColor:
                        result['success'] ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }
}
