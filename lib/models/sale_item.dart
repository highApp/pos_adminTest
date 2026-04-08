class SaleItem {
  final String productId;
  final String productName;
  final double price;
  final double quantity; // Changed to double to support fractional quantities
  final double subtotal;
  final double returnedQuantity; // Number of items returned (changed to double)
  /// Purchase cost **per unit** at checkout (same unit as [price]). Null = legacy sale (no field).
  final double? purchasePrice;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.subtotal,
    this.returnedQuantity = 0,
    this.purchasePrice,
  });

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'subtotal': subtotal,
      'returnedQuantity': returnedQuantity,
    };
    if (purchasePrice != null) {
      m['purchasePrice'] = purchasePrice;
    }
    return m;
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    final rawPp = map['purchasePrice'];
    return SaleItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: (map['quantity'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      returnedQuantity: (map['returnedQuantity'] ?? 0).toDouble(),
      purchasePrice:
          rawPp != null ? (rawPp as num).toDouble() : null,
    );
  }
  
  // Get remaining quantity after returns
  double get remainingQuantity => quantity - returnedQuantity;
  
  // Get remaining subtotal after returns
  double get remainingSubtotal => price * remainingQuantity;
}

