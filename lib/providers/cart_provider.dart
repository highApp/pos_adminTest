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

  /// Minimum quantity for fractional units (e.g. 0.001 kg = 1 gram).
  static const double fractionalMinQuantity = 0.001;
  /// Default increment for +/- buttons (e.g. 0.1 kg = 100 g).
  static const double fractionalIncrement = 0.1;
}

/// Used when loading a draft into the cart (product + quantity).
class DraftLoadItem {
  final Product product;
  final double quantity;

  DraftLoadItem({required this.product, required this.quantity});
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
      final increment = _items[product.id]!.supportsFractionalQuantity ? CartItem.fractionalIncrement : 1.0;

      if (currentQuantity + increment <= product.stock) {
        _items[product.id]!.quantity += increment;
        notifyListeners();
      }
    } else {
      final initialQuantity = CartItem(product: product, quantity: 0, saleType: _saleType).supportsFractionalQuantity ? CartItem.fractionalIncrement : 1.0;
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
      final saleType = _items[productId]!.saleType;
      final updatedProduct = saleType == SaleType.wholesale
          ? originalProduct.copyWith(wholesalePrice: newPrice)
          : originalProduct.copyWith(salePrice: newPrice);

      // Update the cart item with the new product (price only affects this cart)
      _items[productId]!.product = updatedProduct;
      notifyListeners();
    }
  }

  void increaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final increment = cartItem.supportsFractionalQuantity ? CartItem.fractionalIncrement : 1.0;

      if (cartItem.quantity + increment <= cartItem.product.stock) {
        cartItem.quantity += increment;
        notifyListeners();
      }
    }
  }

  void decreaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final decrement = cartItem.supportsFractionalQuantity ? CartItem.fractionalIncrement : 1.0;
      final minQuantity = cartItem.supportsFractionalQuantity ? CartItem.fractionalMinQuantity : 1.0;
      
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

  /// Add a product with a specific quantity (e.g. when loading from draft).
  /// Uses current sale type. Does not check stock so draft can restore out-of-stock items.
  void addItemWithQuantity(Product product, double quantity) {
    if (quantity <= 0) return;
    if (_items.containsKey(product.id)) {
      _items[product.id]!.quantity = quantity;
    } else {
      _items[product.id] = CartItem(
        product: product,
        quantity: quantity,
        saleType: _saleType,
      );
    }
    notifyListeners();
  }

  /// Replace cart with draft data. Clears current cart, sets sale type, then adds each item.
  /// [items] should contain product and quantity; sale type is set once from [saleType].
  void loadFromDraft(SaleType saleType, List<DraftLoadItem> items) {
    _items.clear();
    _saleType = saleType;
    for (final entry in items) {
      _items[entry.product.id] = CartItem(
        product: entry.product,
        quantity: entry.quantity,
        saleType: saleType,
      );
    }
    notifyListeners();
  }

  bool canAddMore(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final increment = cartItem.supportsFractionalQuantity ? CartItem.fractionalIncrement : 1.0;
    return cartItem.quantity + increment <= cartItem.product.stock;
    }
    return true;
  }
}

