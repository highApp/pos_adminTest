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

  /// Dozen pricing in wholesale. Quantity = pieces (12 = 1 dozen). Same for piece and G/KG/ML.
  bool get usesDozenPricing =>
      saleType == SaleType.wholesale && product.dozenPrice != null;

  /// Bundle pricing in wholesale. Quantity = pieces (bundleSize = 1 bundle). Same for piece and G/KG/ML.
  bool get usesBundlePricing =>
      saleType == SaleType.wholesale &&
      product.bundlePrice != null &&
      product.bundleSize != null &&
      product.bundleSize! > 0;

  /// When using dozen/bundle, quantity is always in pieces (12, 24, etc.), so no conversion for stock.
  bool get _quantityIsPiecesForDozenOrBundle =>
      usesDozenPricing || usesBundlePricing;

  double get unitPrice {
    // Per-piece price: dozen = dozenPrice/12, bundle = bundlePrice/bundleSize. Same for all units.
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

  /// Quantity to store in sale and deduct from stock. For dozen/bundle, quantity is already in pieces.
  double get effectiveQuantityForStock => quantity;

  /// For stock checks (e.g. increaseQuantity). Quantity is always in same units as stock.
  double effectiveQuantityFor(double q) => q;

  double get subtotal => unitPrice * quantity;

  /// Quantity step: +/− add/subtract one dozen (12) or one bundle (bundleSize). Same for KG, G, ML, pieces.
  double get quantityStep {
    if (usesDozenPricing) return 12.0;
    if (usesBundlePricing && product.bundleSize != null) return product.bundleSize!.toDouble();
    if (!supportsFractionalQuantity) return 1.0;
    final unit = product.unit.trim().toLowerCase();
    final normalizedUnit = unit == 'gm' ? 'g' : unit;
    if (CartItem.unitUsesSmallFractionDefault(product.unit)) {
      return CartItem.smallFractionUnitStep;
    }
    if (normalizedUnit == 'kg') return 1.0;
    return CartItem.fractionalIncrement;
  }

  /// Min quantity: 1 so you can manually type 10, 30, 48, etc. +/- still use step (12 or bundleSize).
  double get minQuantity {
    if (usesDozenPricing || usesBundlePricing) return 1.0;
    if (!supportsFractionalQuantity) return 1.0;
    if (CartItem.unitUsesSmallFractionDefault(product.unit)) {
      return CartItem.smallFractionUnitStep;
    }
    return CartItem.fractionalMinQuantity;
  }

  /// Fractional qty only when selling by weight/volume and not using dozen/bundle.
  bool get supportsFractionalQuantity {
    if (_quantityIsPiecesForDozenOrBundle) return false;
    final unit = product.unit.trim().toLowerCase();
    final normalizedUnit = unit == 'gm' ? 'g' : unit;
    const weightVolumeUnits = ['kg', 'g', 'l', 'ml', 'lb', 'oz', 'ton'];
    return weightVolumeUnits.contains(normalizedUnit);
  }

  /// g, ml, l (and gm): +/- step and minimum editable line qty (after adding).
  static const double smallFractionUnitStep = 0.1;

  /// g, ml, l: minimum stock to appear in POS / add (below this, e.g. 0.05 g, hide).
  static const double smallFractionMinStockToAdd = 0.1;

  /// Default first-line qty for g, ml, l when stock ≥ this (e.g. 1.0 g); if stock is lower, default is all of it (e.g. 0.5).
  static const double smallFractionDefaultCartQuantity = 1.0;

  /// Grams, millilitres, litres — not kg (kg keeps 1.0 step / default).
  static bool unitUsesSmallFractionDefault(String unit) {
    final u = unit.trim().toLowerCase();
    final n = u == 'gm' ? 'g' : u;
    return n == 'g' || n == 'ml' || n == 'l';
  }

  /// POS grid / add button (g/ml/l need ≥ [smallFractionMinStockToAdd], e.g. 0.5 g is OK).
  static bool hasEnoughStockToAdd(Product product) {
    if (product.stock <= 0) return false;
    if (unitUsesSmallFractionDefault(product.unit) &&
        product.stock < smallFractionMinStockToAdd) {
      return false;
    }
    return true;
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
    // New [CartItem] instances so POS cart tiles' didUpdateWidget sees changes
    // (mutating the same instance makes old/new widget compare equal).
    final next = <String, CartItem>{};
    for (final entry in _items.entries) {
      final old = entry.value;
      final item = CartItem(
        product: old.product,
        quantity: old.quantity,
        saleType: type,
      );
      if (type == SaleType.wholesale) {
        if (!_applyWholesaleQuantitySnap(item) || item.quantity <= 0) {
          continue;
        }
      }
      next[entry.key] = item;
    }
    _items
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  /// When switching to wholesale with dozen/bundle pricing, snap quantity to full
  /// dozens (12) or full bundles so totals match bundle/dozen prices. Per-piece
  /// wholesale keeps quantity unchanged.
  ///
  /// Returns false if the line should be dropped (no wholesale price config).
  bool _applyWholesaleQuantitySnap(CartItem item) {
    final p = item.product;
    final hasBundle = p.bundlePrice != null &&
        p.bundleSize != null &&
        p.bundleSize! > 0;
    if (p.dozenPrice == null && p.wholesalePrice == null && !hasBundle) {
      return false;
    }
    if (p.dozenPrice != null) {
      _snapQuantityToStep(item, 12.0);
      return true;
    }
    if (hasBundle) {
      _snapQuantityToStep(item, p.bundleSize!.toDouble());
      return true;
    }
    return true;
  }

  void _snapQuantityToStep(CartItem item, double step) {
    if (step <= 0) return;
    final stock = item.product.stock;
    var q = item.quantity;
    var snapped = (q / step).ceil() * step;
    if (snapped < step) snapped = step;
    if (snapped > stock) {
      final maxFull = (stock / step).floor() * step;
      snapped = maxFull >= step ? maxFull : stock;
    }
    item.quantity = snapped;
  }

  void addItem(Product product) {
    if (product.stock <= 0) {
      return; // Don't add out of stock items
    }
    if (!CartItem.hasEnoughStockToAdd(product)) {
      return;
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
      // Default quantity: wholesale dozen/bundle → 12 / bundleSize; else 1.0.
      // g/ml/l: stock ≥ 1.0 → default 1.0; stock < 1.0 → default 0.1 (not full stock).
      double initialQuantity = CartItem.smallFractionDefaultCartQuantity;
      if (_saleType == SaleType.wholesale) {
        if (product.dozenPrice != null) {
          initialQuantity = 12.0; // 1 dozen = 12 pieces
        } else if (product.bundlePrice != null &&
            product.bundleSize != null &&
            product.bundleSize! > 0) {
          initialQuantity = product.bundleSize!.toDouble(); // 1 bundle = bundleSize pieces
        }
      }
      if (CartItem.unitUsesSmallFractionDefault(product.unit) &&
          initialQuantity == CartItem.smallFractionDefaultCartQuantity) {
        initialQuantity = product.stock >= CartItem.smallFractionDefaultCartQuantity
            ? CartItem.smallFractionDefaultCartQuantity
            : CartItem.smallFractionUnitStep;
      }
      if (initialQuantity > product.stock) {
        initialQuantity = product.stock;
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

  /// [allowSubStepMinimum]: for weight/volume lines, g/ml/l use 0.1 as normal
  /// [CartItem.minQuantity] for +/- — set true when applying weight-calculator
  /// results so amounts like 0.0357 kg are allowed (floor [CartItem.fractionalMinQuantity]).
  void updateQuantity(
    String productId,
    double quantity, {
    bool allowSubStepMinimum = false,
  }) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final product = cartItem.product;
      final minQ = allowSubStepMinimum && cartItem.supportsFractionalQuantity
          ? CartItem.fractionalMinQuantity
          : cartItem.minQuantity;
      if (quantity > 0 && quantity >= minQ && quantity <= product.stock) {
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
      final newQty = cartItem.quantity + increment;
      final effectiveNeeded = cartItem.effectiveQuantityFor(newQty);

      if (effectiveNeeded <= cartItem.product.stock) {
        cartItem.quantity += increment;
        notifyListeners();
      }
    }
  }

  void decreaseQuantity(String productId) {
    if (_items.containsKey(productId)) {
      final cartItem = _items[productId]!;
      final decrement = cartItem.quantityStep;
      final minQty = cartItem.minQuantity;

      if (cartItem.quantity <= minQty) {
        removeItem(productId);
        return;
      }
      // For dozen/bundle at exactly one step (12 or bundleSize): minus does nothing
      if ((cartItem.usesDozenPricing || cartItem.usesBundlePricing) && cartItem.quantity == decrement) {
        return;
      }
      double newQty = cartItem.quantity - decrement;
      if (cartItem.usesDozenPricing || cartItem.usesBundlePricing) {
        if (newQty < minQty) newQty = minQty;
        else if (newQty < decrement) newQty = decrement;
      } else if (newQty < minQty) {
        newQty = minQty;
      }
      cartItem.quantity = newQty;
      notifyListeners();
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
      final effectiveNeeded = cartItem.effectiveQuantityFor(cartItem.quantity + increment);
      return effectiveNeeded <= cartItem.product.stock;
    }
    return true;
  }

  /// Syncs each cart line with the latest catalog [Product] from Firestore
  /// (stock, sale/wholesale/dozen/bundle prices, purchase price, names, etc.).
  /// POS line uses server data so product edits and buyer-bill stock/avg updates apply in real time.
  void syncProductsFromServer(List<Product> latestProducts) {
    if (_items.isEmpty) return;
    final map = {for (final p in latestProducts) p.id: p};
    final keys = _items.keys.toList();
    var changed = false;
    for (final key in keys) {
      final item = _items[key];
      if (item == null) continue;
      final latest = map[key];
      if (latest == null) continue;

      if (latest.stock <= 0) {
        _items.remove(key);
        changed = true;
        continue;
      }
      if (CartItem.unitUsesSmallFractionDefault(latest.unit) &&
          latest.stock < CartItem.smallFractionMinStockToAdd) {
        _items.remove(key);
        changed = true;
        continue;
      }

      var newQty = item.quantity;
      if (newQty > latest.stock) {
        newQty = latest.stock;
      }

      if (!_sameCatalogProduct(item.product, latest) || newQty != item.quantity) {
        _items[key] = CartItem(
          product: latest,
          quantity: newQty,
          saleType: item.saleType,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  bool _sameCatalogProduct(Product a, Product b) {
    if (identical(a, b)) return true;
    if (a.stock != b.stock ||
        a.salePrice != b.salePrice ||
        a.purchasePrice != b.purchasePrice ||
        a.wholesalePrice != b.wholesalePrice ||
        a.dozenPrice != b.dozenPrice ||
        a.bundlePrice != b.bundlePrice ||
        a.bundleSize != b.bundleSize ||
        a.minimumSalePrice != b.minimumSalePrice ||
        a.unit != b.unit ||
        a.name != b.name ||
        a.updatedAt != b.updatedAt) {
      return false;
    }
    final an = a.names;
    final bn = b.names;
    if ((an == null) != (bn == null)) return false;
    if (an != null && bn != null) {
      if (an.length != bn.length) return false;
      for (final e in an.entries) {
        if (bn[e.key] != e.value) return false;
      }
    }
    return true;
  }
}

