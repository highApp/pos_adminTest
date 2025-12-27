class BuyerBillItem {
  final String id;
  final String itemName;
  final double price;
  final String unit;
  final double quantity;
  final double expense;
  final double subtotal;
  final DateTime? date;

  BuyerBillItem({
    required this.id,
    required this.itemName,
    required this.price,
    required this.unit,
    required this.quantity,
    required this.expense,
    required this.subtotal,
    this.date,
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
    );
  }
}
