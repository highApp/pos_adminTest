class BuyerBillItem {
  final String id;
  final String itemName;
  final double price;
  final String unit;
  final double quantity;
  final double expense;
  final double subtotal;
  final DateTime? date;
  /// Free quantity added to total (does not affect price)
  final double bonusQty;
  /// Pack size (qty per pack) - for edit restore
  final double packSize;
  /// Packing type (Box, Carton, etc.) - for edit restore
  final String? packingType;
  /// Category for new product creation when bill is saved
  final String? category;

  BuyerBillItem({
    required this.id,
    required this.itemName,
    required this.price,
    required this.unit,
    required this.quantity,
    required this.expense,
    required this.subtotal,
    this.date,
    this.bonusQty = 0,
    this.packSize = 1,
    this.packingType,
    this.category,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemName': itemName,
      'price': price,
      'unit': unit,
      'quantity': quantity,
      'expense': expense,
      'subtotal': subtotal,
      'date': date?.toIso8601String(),
      'bonusQty': bonusQty,
      'packSize': packSize,
      'packingType': packingType,
      'category': category,
    };
  }

  factory BuyerBillItem.fromMap(Map<String, dynamic> map) {
    return BuyerBillItem(
      id: map['id'] ?? '',
      itemName: map['itemName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      unit: map['unit'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      expense: (map['expense'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      date: map['date'] != null ? DateTime.parse(map['date']) : null,
      bonusQty: (map['bonusQty'] ?? 0).toDouble(),
      packSize: (map['packSize'] ?? 1).toDouble(),
      packingType: map['packingType'] as String?,
      category: map['category'] as String?,
    );
  }
}
