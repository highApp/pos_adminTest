import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/seller_order.dart';

class SellerCartItem {
  final Product product;
  double quantity;

  SellerCartItem({
    required this.product,
    this.quantity = 1.0,
  });

  double get wholesalePrice => product.wholesalePrice ?? product.salePrice;
  double get subtotal => wholesalePrice * quantity;
  double get profit => (wholesalePrice - product.purchasePrice) * quantity;
}

class SellerCartProvider with ChangeNotifier {
  final Map<String, SellerCartItem> _items = {};
  String? _editingOrderId;

  Map<String, SellerCartItem> get items => {..._items};

  /// Non-null when cart is loaded for editing a pending order.
  String? get editingOrderId => _editingOrderId;

  int get itemCount => _items.length;

  double get totalItems {
    return _items.values.fold(0.0, (sum, item) => sum + item.quantity);
  }

  double get totalAmount {
    return _items.values.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  double get totalProfit {
    return _items.values.fold(0.0, (sum, item) => sum + item.profit);
  }

  void addItem(Product product) {
    if (product.stock <= 0) {
      return;
    }

    // Only products with wholesale price can be added
    if (product.wholesalePrice == null) {
      return;
    }

    if (_items.containsKey(product.id)) {
      final currentQuantity = _items[product.id]!.quantity;
      if (currentQuantity + 1 <= product.stock) {
        _items[product.id]!.quantity += 1;
        notifyListeners();
      }
    } else {
      _items[product.id] = SellerCartItem(product: product, quantity: 1);
      notifyListeners();
    }
  }

  void removeItem(String productId) {
    _items.remove(productId);
    notifyListeners();
  }

  void updateQuantity(String productId, double quantity) {
    if (_items.containsKey(productId)) {
      final product = _items[productId]!.product;
      if (quantity > 0 && quantity <= product.stock) {
        _items[productId]!.quantity = quantity;
        notifyListeners();
      }
    }
  }

  void increaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      if (cartItem.quantity + 1 <= cartItem.product.stock) {
        cartItem.quantity += 1;
        notifyListeners();
      }
    }
  }

  void decreaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      if (cartItem.quantity > 1) {
        cartItem.quantity -= 1;
        notifyListeners();
      } else {
        removeItem(productId);
      }
    }
  }

  /// Load an existing (pending) order into the cart for editing. Replaces current cart.
  void loadOrderForEdit(SellerOrder order, List<Product> products) {
    _editingOrderId = order.id;
    _items.clear();
    final byId = {for (var p in products) p.id: p};
    for (final item in order.items) {
      final p = byId[item.productId];
      if (p != null) {
        _items[p.id] = SellerCartItem(product: p, quantity: item.quantity);
      }
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _editingOrderId = null;
    notifyListeners();
  }

  bool canAddMore(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      return cartItem.quantity + 1 <= cartItem.product.stock;
    }
    return true;
  }
}
