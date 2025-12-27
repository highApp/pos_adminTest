import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/seller_order.dart';
import '../models/balance_entry.dart';
import '../services/product_service.dart';
import '../services/balance_service.dart';

class SellerOrderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'seller_orders';
  final ProductService _productService = ProductService();
  final BalanceService _balanceService = BalanceService();

  // Create new order
  Future<Map<String, dynamic>> createOrder(SellerOrder order) async {
    try {
      await _firestore.collection(_collection).doc(order.id).set(order.toMap());
      
      return {
        'success': true,
        'message': 'Order placed successfully',
        'orderId': order.id,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to create order: $e',
      };
    }
  }

  // Get seller's orders
  Stream<List<SellerOrder>> getSellerOrders(String sellerId) {
    return _firestore
        .collection(_collection)
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs.map((doc) {
        return SellerOrder.fromMap(doc.data());
      }).toList();
      
      // Sort in memory instead of Firestore (avoids index requirement)
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  // Get all orders (for admin)
  Stream<List<SellerOrder>> getAllOrders() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return SellerOrder.fromMap(doc.data());
      }).toList();
    });
  }

  // Cancel order (seller can only cancel pending orders)
  Future<Map<String, dynamic>> cancelOrder(
    String orderId,
    String cancelReason,
  ) async {
    try {
      final doc = await _firestore.collection(_collection).doc(orderId).get();
      
      if (!doc.exists) {
        return {
          'success': false,
          'message': 'Order not found',
        };
      }

      final order = SellerOrder.fromMap(doc.data()!);

      if (order.status != OrderStatus.pending) {
        return {
          'success': false,
          'message': 'Only pending orders can be cancelled',
        };
      }

      await _firestore.collection(_collection).doc(orderId).update({
        'status': OrderStatus.cancelled.name,
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelReason': cancelReason,
      });

      return {
        'success': true,
        'message': 'Order cancelled successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to cancel order: $e',
      };
    }
  }

  // Confirm order (admin only)
  Future<Map<String, dynamic>> confirmOrder(String orderId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(orderId).get();
      
      if (!doc.exists) {
        return {
          'success': false,
          'message': 'Order not found',
        };
      }

      final order = SellerOrder.fromMap(doc.data()!);

      if (order.status != OrderStatus.pending) {
        return {
          'success': false,
          'message': 'Only pending orders can be confirmed',
        };
      }

      await _firestore.collection(_collection).doc(orderId).update({
        'status': OrderStatus.confirmed.name,
        'confirmedAt': DateTime.now().toIso8601String(),
      });

      return {
        'success': true,
        'message': 'Order confirmed successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to confirm order: $e',
      };
    }
  }

  // Complete order (admin only) - Updates stock and profit
  Future<Map<String, dynamic>> completeOrder(String orderId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(orderId).get();
      
      if (!doc.exists) {
        return {
          'success': false,
          'message': 'Order not found',
        };
      }

      final order = SellerOrder.fromMap(doc.data()!);

      if (order.status == OrderStatus.completed) {
        return {
          'success': false,
          'message': 'Order is already completed',
        };
      }

      if (order.status == OrderStatus.cancelled) {
        return {
          'success': false,
          'message': 'Cannot complete a cancelled order',
        };
      }

      // Update stock for each item
      for (var item in order.items) {
        try {
          await _productService.updateStock(item.productId, -item.quantity);
        } catch (e) {
          return {
            'success': false,
            'message': 'Failed to update stock for ${item.productName}: $e',
          };
        }
      }

      // Add revenue to balance (wholesale order)
      final balanceEntry = BalanceEntry(
        id: const Uuid().v4(),
        amount: order.total,
        description: 'Wholesale Order - ${order.sellerName} (Profit: Rs. ${order.profit.toStringAsFixed(2)})',
        date: DateTime.now(),
        createdAt: DateTime.now(),
      );

      try {
        await _balanceService.addBalanceEntry(balanceEntry);
      } catch (e) {
        // Rollback stock changes if balance update fails
        for (var item in order.items) {
          await _productService.updateStock(item.productId, item.quantity);
        }
        return {
          'success': false,
          'message': 'Failed to add revenue to balance: $e',
        };
      }

      // Mark order as completed
      await _firestore.collection(_collection).doc(orderId).update({
        'status': OrderStatus.completed.name,
        'completedAt': DateTime.now().toIso8601String(),
      });

      return {
        'success': true,
        'message': 'Order completed successfully! Stock updated and profit added.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to complete order: $e',
      };
    }
  }

  // Cancel order by admin - Reverses stock if needed
  Future<Map<String, dynamic>> adminCancelOrder(
    String orderId,
    String cancelReason,
  ) async {
    try {
      final doc = await _firestore.collection(_collection).doc(orderId).get();
      
      if (!doc.exists) {
        return {
          'success': false,
          'message': 'Order not found',
        };
      }

      final order = SellerOrder.fromMap(doc.data()!);

      if (order.status == OrderStatus.cancelled) {
        return {
          'success': false,
          'message': 'Order is already cancelled',
        };
      }

      // If order was completed, reverse the stock AND profit
      if (order.status == OrderStatus.completed) {
        // Reverse stock
        for (var item in order.items) {
          try {
            await _productService.updateStock(item.productId, item.quantity);
          } catch (e) {
            return {
              'success': false,
              'message': 'Failed to reverse stock for ${item.productName}: $e',
            };
          }
        }

        // Remove revenue from balance by adding a negative entry
        final reversalEntry = BalanceEntry(
          id: const Uuid().v4(),
          amount: -order.total,
          description: 'Cancelled Wholesale Order - ${order.sellerName} (Refund)',
          date: DateTime.now(),
          createdAt: DateTime.now(),
        );

        try {
          await _balanceService.addBalanceEntry(reversalEntry);
        } catch (e) {
          return {
            'success': false,
            'message': 'Failed to reverse revenue: $e',
          };
        }
      }

      // Mark order as cancelled
      await _firestore.collection(_collection).doc(orderId).update({
        'status': OrderStatus.cancelled.name,
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelReason': cancelReason,
      });

      return {
        'success': true,
        'message': order.status == OrderStatus.completed
            ? 'Order cancelled, stock and profit reversed'
            : 'Order cancelled successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to cancel order: $e',
      };
    }
  }

  // Get order statistics (for admin dashboard)
  Future<Map<String, dynamic>> getOrderStatistics() async {
    try {
      final snapshot = await _firestore.collection(_collection).get();
      final orders = snapshot.docs.map((doc) => SellerOrder.fromMap(doc.data())).toList();

      int pending = 0;
      int confirmed = 0;
      int completed = 0;
      int cancelled = 0;
      double totalRevenue = 0;
      double totalProfit = 0;

      for (var order in orders) {
        switch (order.status) {
          case OrderStatus.pending:
            pending++;
            break;
          case OrderStatus.confirmed:
            confirmed++;
            break;
          case OrderStatus.completed:
            completed++;
            totalRevenue += order.total;
            totalProfit += order.profit;
            break;
          case OrderStatus.cancelled:
            cancelled++;
            break;
        }
      }

      return {
        'pending': pending,
        'confirmed': confirmed,
        'completed': completed,
        'cancelled': cancelled,
        'totalRevenue': totalRevenue,
        'totalProfit': totalProfit,
        'totalOrders': orders.length,
      };
    } catch (e) {
      return {
        'pending': 0,
        'confirmed': 0,
        'completed': 0,
        'cancelled': 0,
        'totalRevenue': 0.0,
        'totalProfit': 0.0,
        'totalOrders': 0,
      };
    }
  }
}
