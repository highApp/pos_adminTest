enum OrderStatus {
  pending,
  confirmed,
  completed,
  cancelled,
}

class SellerOrder {
  final String id;
  final String sellerId;
  final String sellerName;
  final String sellerPhone;
  final String sellerLocation;
  final List<OrderItem> items;
  final double total;
  final double profit;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  SellerOrder({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.sellerPhone,
    required this.sellerLocation,
    required this.items,
    required this.total,
    required this.profit,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerPhone': sellerPhone,
      'sellerLocation': sellerLocation,
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'profit': profit,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'confirmedAt': confirmedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'cancelledAt': cancelledAt?.toIso8601String(),
      'cancelReason': cancelReason,
    };
  }

  factory SellerOrder.fromMap(Map<String, dynamic> map) {
    return SellerOrder(
      id: map['id'] ?? '',
      sellerId: map['sellerId'] ?? '',
      sellerName: map['sellerName'] ?? '',
      sellerPhone: map['sellerPhone'] ?? '',
      sellerLocation: map['sellerLocation'] ?? '',
      items: (map['items'] as List<dynamic>?)
              ?.map((item) => OrderItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      total: (map['total'] ?? 0).toDouble(),
      profit: (map['profit'] ?? 0).toDouble(),
      status: OrderStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => OrderStatus.pending,
      ),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      confirmedAt: map['confirmedAt'] != null
          ? DateTime.parse(map['confirmedAt'])
          : null,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'])
          : null,
      cancelledAt: map['cancelledAt'] != null
          ? DateTime.parse(map['cancelledAt'])
          : null,
      cancelReason: map['cancelReason'],
    );
  }
}

class OrderItem {
  final String productId;
  final String productName;
  final double wholesalePrice;
  final double quantity;
  final double subtotal;
  final double purchasePrice;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.wholesalePrice,
    required this.quantity,
    required this.subtotal,
    required this.purchasePrice,
  });

  double get profit => (wholesalePrice - purchasePrice) * quantity;

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'wholesalePrice': wholesalePrice,
      'quantity': quantity,
      'subtotal': subtotal,
      'purchasePrice': purchasePrice,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      wholesalePrice: (map['wholesalePrice'] ?? 0).toDouble(),
      quantity: (map['quantity'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      purchasePrice: (map['purchasePrice'] ?? 0).toDouble(),
    );
  }
}
