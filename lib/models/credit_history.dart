class CreditHistory {
  final String id;
  final String sellerId;
  final double amount; // Positive for credit added, negative for credit reduced
  final double balanceBefore;
  final double balanceAfter;
  final String type; // 'added', 'reduced', 'used', 'payment'
  final String? description;
  final String? referenceNumber;
  final DateTime createdAt;

  CreditHistory({
    required this.id,
    required this.sellerId,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.type,
    this.description,
    this.referenceNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'amount': amount,
      'balanceBefore': balanceBefore,
      'balanceAfter': balanceAfter,
      'type': type,
      'description': description,
      'referenceNumber': referenceNumber,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CreditHistory.fromMap(Map<String, dynamic> map) {
    return CreditHistory(
      id: map['id'] ?? '',
      sellerId: map['sellerId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      balanceBefore: (map['balanceBefore'] ?? 0).toDouble(),
      balanceAfter: (map['balanceAfter'] ?? 0).toDouble(),
      type: map['type'] ?? 'added',
      description: map['description'],
      referenceNumber: map['referenceNumber'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  CreditHistory copyWith({
    String? id,
    String? sellerId,
    double? amount,
    double? balanceBefore,
    double? balanceAfter,
    String? type,
    String? description,
    String? referenceNumber,
    DateTime? createdAt,
  }) {
    return CreditHistory(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      amount: amount ?? this.amount,
      balanceBefore: balanceBefore ?? this.balanceBefore,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      type: type ?? this.type,
      description: description ?? this.description,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

