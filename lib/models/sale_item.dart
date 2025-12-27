class SaleItem {
  final String productId;
  final String productName;
  final double price;
  final double quantity; // Changed to double to support fractional quantities
  final double subtotal;
  final double returnedQuantity; // Number of items returned (changed to double)

  SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.subtotal,
    this.returnedQuantity = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'subtotal': subtotal,
      'returnedQuantity': returnedQuantity,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: (map['quantity'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      returnedQuantity: (map['returnedQuantity'] ?? 0).toDouble(),
    );
  }
  
  // Get remaining quantity after returns
  double get remainingQuantity => quantity - returnedQuantity;
  
  // Get remaining subtotal after returns
  double get remainingSubtotal => price * remainingQuantity;
}

