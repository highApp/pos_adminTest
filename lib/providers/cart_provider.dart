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

  bool get _isPieceUnit {
    final unit = product.unit.trim().toLowerCase();
    if (unit.isEmpty) return true;
    return unit == 'piece' || unit == 'pieces' || unit == 'pc' || unit == 'pcs';
  }

  bool get usesDozenPricing =>
      saleType == SaleType.wholesale && _isPieceUnit && product.dozenPrice != null;

  bool get usesBundlePricing =>
      saleType == SaleType.wholesale &&
      _isPieceUnit &&
      product.bundlePrice != null &&
      product.bundleSize != null &&
      product.bundleSize! > 0;

  double get unitPrice {
    // Per-piece price for subtotal = unitPrice * quantity.
    // Dozen: price per 12. Bundle: price per bundleSize. Else wholesale per piece.
    if (saleType == SaleType.wholesale) {
      if (usesDozenPricing) return product.dozenPrice! / 12.0;
      if (usesBundlePricing) return product.bundlePrice! / product.bundleSize!;
      if (product.wholesalePrice != null) return product.wholesalePrice!;
    }
    return product.salePrice;
  }

  /// What to show in UI as the "unit price" (dozen price, bundle price, or per-unit).
  double get displayUnitPrice {
    if (saleType == SaleType.wholesale && usesDozenPricing) return product.dozenPrice!;
    if (saleType == SaleType.wholesale && usesBundlePricing) return product.bundlePrice!;
    return unitPrice;
  }

  /// Bundle size for display (e.g. "bundle (10)").
  int? get displayBundleSize => product.bundleSize;

  double get subtotal => unitPrice * quantity;

  /// Quantity step for +/- buttons. For g, ml, kg, L: step 1 (1 gram, 1 ml, 1 kg, 1 L). Pieces: 1.
  double get quantityStep {
    if (!supportsFractionalQuantity) return 1.0;
    final unit = product.unit.trim().toLowerCase();
    final normalizedUnit = unit == 'gm' ? 'g' : unit;
    // For g, ml, kg, L: plus/minus add 1 unit (1g, 1ml, 1kg, 1L)
    const oneUnitStep = ['g', 'ml', 'kg', 'l'];
    return oneUnitStep.contains(normalizedUnit) ? 1.0 : CartItem.fractionalIncrement;
  }

  double get minQuantity {
    return supportsFractionalQuantity ? CartItem.fractionalMinQuantity : 1.0;
  }

  // Helper method to check if this product supports fractional quantities (decimals like 0.5, 1.111)
  bool get supportsFractionalQuantity {
    final unit = product.unit.trim().toLowerCase();
    final normalizedUnit = unit == 'gm' ? 'g' : unit;
    const weightVolumeUnits = ['kg', 'g', 'l', 'ml', 'lb', 'oz', 'ton'];
    return weightVolumeUnits.contains(normalizedUnit);
  }

  /// Minimum quantity for fractional units (e.g. 0.001 kg = 1 gram).
  static const double fractionalMinQuantity = 0.001;
  /// Fallback increment for other fractional units (e.g. 0.1 for lb, oz, ton).
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

    // In wholesale mode, require at least one: wholesale, dozen, or bundle price.
    final hasBundle = product.bundlePrice != null &&
        product.bundleSize != null &&
        product.bundleSize! > 0;
    if (_saleType == SaleType.wholesale &&
        product.wholesalePrice == null &&
        product.dozenPrice == null &&
        !hasBundle) {
      return;
    }

    if (_items.containsKey(product.id)) {
      // Check if we can add more
      final cartItem = _items[product.id]!;
      final currentQuantity = cartItem.quantity;
      final increment = cartItem.quantityStep;

      if (currentQuantity + increment <= product.stock) {
        cartItem.quantity += increment;
        notifyListeners();
      }
    } else {
      // Default quantity: 1 dozen (12), 1 bundle (bundleSize), or 1 unit.
      final isPieceUnit = () {
        final unit = product.unit.trim().toLowerCase();
        if (unit.isEmpty) return true;
        return unit == 'piece' || unit == 'pieces' || unit == 'pc' || unit == 'pcs';
      }();
      double initialQuantity = 1.0;
      if (_saleType == SaleType.wholesale && isPieceUnit) {
        if (product.dozenPrice != null) {
          initialQuantity = 12.0;
        } else if (product.bundlePrice != null &&
            product.bundleSize != null &&
            product.bundleSize! > 0) {
          initialQuantity = product.bundleSize!.toDouble();
        }
      }
      _items[product.id] =
          CartItem(product: product, quantity: initialQuantity, saleType: _saleType);
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
      final cartItem = _items[productId]!;
      Product updatedProduct;
      if (saleType == SaleType.wholesale) {
        if (cartItem.usesDozenPricing) {
          updatedProduct = originalProduct.copyWith(dozenPrice: newPrice);
        } else if (cartItem.usesBundlePricing) {
          updatedProduct = originalProduct.copyWith(bundlePrice: newPrice);
        } else {
          updatedProduct = originalProduct.copyWith(wholesalePrice: newPrice);
        }
      } else {
        updatedProduct = originalProduct.copyWith(salePrice: newPrice);
      }

      // Update the cart item with the new product (price only affects this cart)
      _items[productId]!.product = updatedProduct;
      notifyListeners();
    }
  }

  void increaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final increment = cartItem.quantityStep;

      if (cartItem.quantity + increment <= cartItem.product.stock) {
        cartItem.quantity += increment;
        notifyListeners();
      }
    }
  }

  void decreaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final decrement = cartItem.quantityStep;
      final minQuantity = cartItem.minQuantity;
      
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
      final increment = cartItem.quantityStep;
      return cartItem.quantity + increment <= cartItem.product.stock;
    }
    return true;
  }
}

