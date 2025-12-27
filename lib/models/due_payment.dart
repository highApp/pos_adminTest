class DuePayment {
  final String id;
  final String sellerId;
  final String saleId;
  final double totalAmount;
  final double amountPaid;
  final double dueAmount;
  final DateTime createdAt;
  final bool isPaid;
  final DateTime? paidAt;

  DuePayment({
    required this.id,
    required this.sellerId,
    required this.saleId,
    required this.totalAmount,
    required this.amountPaid,
    required this.dueAmount,
    required this.createdAt,
    this.isPaid = false,
    this.paidAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'saleId': saleId,
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'dueAmount': dueAmount,
      'createdAt': createdAt.toIso8601String(),
      'isPaid': isPaid,
      'paidAt': paidAt?.toIso8601String(),
    };
  }

  factory DuePayment.fromMap(Map<String, dynamic> map) {
    return DuePayment(
      id: map['id'] ?? '',
      sellerId: map['sellerId'] ?? '',
      saleId: map['saleId'] ?? '',
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      amountPaid: (map['amountPaid'] ?? 0).toDouble(),
      dueAmount: (map['dueAmount'] ?? 0).toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      isPaid: map['isPaid'] ?? false,
      paidAt: map['paidAt'] != null ? DateTime.parse(map['paidAt']) : null,
    );
  }
}

