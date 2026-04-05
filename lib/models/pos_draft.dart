import '../providers/cart_provider.dart';

/// Single line item in a POS draft (product + quantity + price at save time).
///
/// [unitPrice] stores the **display** unit price used in the cart (same as
/// [CartItem.displayUnitPrice]): per piece for regular/wholesale, per dozen
/// total for dozen mode, per bundle total for bundle mode. This matches
/// [CartProvider.updatePrice] when restoring.
class PosDraftItem {
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final SaleType saleType;

  /// Line total at save time (matches [CartItem.subtotal]). Persisted so draft
  /// list totals stay correct when [unitPrice] is display dozen/bundle price.
  final double lineSubtotal;

  PosDraftItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.saleType,
    required this.lineSubtotal,
  });

  double get subtotal => lineSubtotal;

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'displayUnitPrice': unitPrice,
      'lineSubtotal': lineSubtotal,
      'saleType': saleType.name,
    };
  }

  factory PosDraftItem.fromMap(Map<String, dynamic> map) {
    final saleTypeStr = (map['saleType']?.toString() ?? 'regular').trim();
    final priceVal = map['displayUnitPrice'] ?? map['unitPrice'];
    final parsedUnit = priceVal != null ? (priceVal as num).toDouble() : 0.0;
    final qty = (map['quantity'] ?? 0).toDouble();
    final storedSub = map['lineSubtotal'];
    final lineSub = storedSub != null
        ? (storedSub as num).toDouble()
        : parsedUnit * qty;
    return PosDraftItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      quantity: qty,
      unitPrice: parsedUnit,
      saleType: saleTypeStr == 'wholesale' ? SaleType.wholesale : SaleType.regular,
      lineSubtotal: lineSub,
    );
  }
}

/// A saved POS order draft (not yet paid).
class PosDraft {
  final String id;
  final DateTime createdAt;
  final SaleType saleType;
  final List<PosDraftItem> items;

  /// Optional label (e.g. customer or table) shown in the drafts list.
  final String? name;

  PosDraft({
    required this.id,
    required this.createdAt,
    required this.saleType,
    required this.items,
    this.name,
  });

  int get itemCount => items.length;

  double get totalAmount {
    return items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'saleType': saleType.name,
      'items': items.map((e) => e.toMap()).toList(),
    };
    final n = name?.trim();
    if (n != null && n.isNotEmpty) {
      map['name'] = n;
    }
    return map;
  }

  factory PosDraft.fromMap(Map<String, dynamic> map) {
    final itemsList = map['items'];
    final List<PosDraftItem> parsedItems = [];
    if (itemsList is List) {
      for (var e in itemsList) {
        if (e is Map) {
          parsedItems.add(
            PosDraftItem.fromMap(Map<String, dynamic>.from(e as Map)),
          );
        }
      }
    }
    var saleTypeStr = (map['saleType']?.toString() ?? '').trim();
    if (saleTypeStr.isEmpty && parsedItems.isNotEmpty) {
      final first = parsedItems.first.saleType;
      final allSame = parsedItems.every((i) => i.saleType == first);
      saleTypeStr = allSame ? first.name : 'regular';
    }
    if (saleTypeStr.isEmpty) saleTypeStr = 'regular';
    final rawName = map['name']?.toString().trim();
    final parsedName =
        (rawName != null && rawName.isNotEmpty) ? rawName : null;
    return PosDraft(
      id: map['id']?.toString() ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'].toString())
          : DateTime.now(),
      saleType: saleTypeStr == 'wholesale' ? SaleType.wholesale : SaleType.regular,
      items: parsedItems,
      name: parsedName,
    );
  }
}
