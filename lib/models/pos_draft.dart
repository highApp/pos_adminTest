import '../providers/cart_provider.dart';

/// Single line item in a POS draft (product + quantity + price at save time).
class PosDraftItem {
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final SaleType saleType;

  PosDraftItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.saleType,
  });

  double get subtotal => unitPrice * quantity;

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'saleType': saleType.name,
    };
  }

  factory PosDraftItem.fromMap(Map<String, dynamic> map) {
    final saleTypeStr = map['saleType']?.toString() ?? 'regular';
    return PosDraftItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      unitPrice: (map['unitPrice'] ?? 0).toDouble(),
      saleType: saleTypeStr == 'wholesale' ? SaleType.wholesale : SaleType.regular,
    );
  }
}

/// A saved POS order draft (not yet paid).
class PosDraft {
  final String id;
  final DateTime createdAt;
  final SaleType saleType;
  final List<PosDraftItem> items;

  PosDraft({
    required this.id,
    required this.createdAt,
    required this.saleType,
    required this.items,
  });

  int get itemCount => items.length;

  double get totalAmount {
    return items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'saleType': saleType.name,
      'items': items.map((e) => e.toMap()).toList(),
    };
  }

  factory PosDraft.fromMap(Map<String, dynamic> map) {
    final saleTypeStr = map['saleType']?.toString() ?? 'regular';
    final itemsList = map['items'];
    final List<PosDraftItem> parsedItems = [];
    if (itemsList is List) {
      for (var e in itemsList) {
        if (e is Map<String, dynamic>) {
          parsedItems.add(PosDraftItem.fromMap(e));
        }
      }
    }
    return PosDraft(
      id: map['id'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      saleType: saleTypeStr == 'wholesale' ? SaleType.wholesale : SaleType.regular,
      items: parsedItems,
    );
  }
}
