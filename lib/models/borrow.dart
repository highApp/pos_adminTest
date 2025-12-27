class Borrow {
  final String id;
  final String type; // 'borrowed' (money borrowed from someone) or 'lent' (money lent to someone)
  final String personName; // Name of the person who borrowed/lent
  final String description;
  final double amount;
  final DateTime createdAt;
  final bool isPaid; // Whether the borrow/lend has been paid back
  final DateTime? paidAt;

  Borrow({
    required this.id,
    required this.type,
    required this.personName,
    required this.description,
    required this.amount,
    required this.createdAt,
    this.isPaid = false,
    this.paidAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'personName': personName,
      'description': description,
      'amount': amount,
      'createdAt': createdAt.toIso8601String(),
      'isPaid': isPaid,
      'paidAt': paidAt?.toIso8601String(),
    };
  }

  factory Borrow.fromMap(Map<String, dynamic> map) {
    return Borrow(
      id: map['id'] ?? '',
      type: map['type'] ?? 'borrowed',
      personName: map['personName'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      isPaid: map['isPaid'] ?? false,
      paidAt: map['paidAt'] != null ? DateTime.parse(map['paidAt']) : null,
    );
  }

  String get typeDisplayName {
    switch (type) {
      case 'borrowed':
        return 'Borrowed';
      case 'lent':
        return 'Lent';
      default:
        return type;
    }
  }

  String get typeIcon {
    switch (type) {
      case 'borrowed':
        return '📥';
      case 'lent':
        return '📤';
      default:
        return '💰';
    }
  }
}

