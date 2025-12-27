import 'package:flutter/foundation.dart';
import '../models/product.dart';

enum SaleType { regular, wholesale }

class CartItem {
  Product product;
  double quantity; // Changed from int to double to support fractional quantities
  SaleType saleType;

  CartItem({
    required this.product,
    this.quantity = 1.0,
    this.saleType = SaleType.regular,
  });

  double get unitPrice {
    if (saleType == SaleType.wholesale && product.wholesalePrice != null) {
      return product.wholesalePrice!;
    }
    return product.salePrice;
  }

  double get subtotal => unitPrice * quantity;
  
  // Helper method to check if this product supports fractional quantities
  bool get supportsFractionalQuantity {
    // Support fractional quantities for weight-based units (kg, g, L, ml, etc.)
    final weightUnits = ['kg', 'g', 'l', 'ml', 'lb', 'oz', 'ton'];
    return weightUnits.contains(product.unit.toLowerCase());
  }
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};
  SaleType _saleType = SaleType.regular;

  Map<String, CartItem> get items => {..._items};
  SaleType get saleType => _saleType;

  int get itemCount => _items.length;

  double get totalItems {
    return _items.values.fold(0.0, (sum, item) => sum + item.quantity);
  }

  double get totalAmount {
    return _items.values.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  void setSaleType(SaleType type) {
    _saleType = type;
    // Update all existing cart items with new sale type
    for (var item in _items.values) {
      item.saleType = type;
    }
    notifyListeners();
  }

  void addItem(Product product) {
    if (product.stock <= 0) {
      return; // Don't add out of stock items
    }

    // Check if wholesale is selected but product doesn't have wholesale price
    if (_saleType == SaleType.wholesale && product.wholesalePrice == null) {
      return; // Don't add products without wholesale price when in wholesale mode
    }

    if (_items.containsKey(product.id)) {
      // Check if we can add more
      final currentQuantity = _items[product.id]!.quantity;
      final increment = _items[product.id]!.supportsFractionalQuantity ? 0.1 : 1.0;
      
      if (currentQuantity + increment <= product.stock) {
        _items[product.id]!.quantity += increment;
        notifyListeners();
      }
    } else {
      final initialQuantity = CartItem(product: product, quantity: 0, saleType: _saleType).supportsFractionalQuantity ? 0.1 : 1.0;
      _items[product.id] = CartItem(product: product, quantity: initialQuantity, saleType: _saleType);
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

  void updatePrice(String productId, double newPrice) {
    if (_items.containsKey(productId)) {
      // Create a new product with updated price for this cart session only
      final originalProduct = _items[productId]!.product;
      final updatedProduct = originalProduct.copyWith(salePrice: newPrice);
      
      // Update the cart item with the new product (price only affects this cart)
      _items[productId]!.product = updatedProduct;
      notifyListeners();
    }
  }

  void increaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final increment = cartItem.supportsFractionalQuantity ? 0.1 : 1.0;
      
      if (cartItem.quantity + increment <= cartItem.product.stock) {
        cartItem.quantity += increment;
        notifyListeners();
      }
    }
  }

  void decreaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final decrement = cartItem.supportsFractionalQuantity ? 0.1 : 1.0;
      final minQuantity = cartItem.supportsFractionalQuantity ? 0.1 : 1.0;
      
      if (cartItem.quantity > minQuantity) {
        cartItem.quantity -= decrement;
        notifyListeners();
      } else {
        removeItem(productId);
      }
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  bool canAddMore(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final increment = cartItem.supportsFractionalQuantity ? 0.1 : 1.0;
      return cartItem.quantity + increment <= cartItem.product.stock;
    }
    return true;
  }
}

