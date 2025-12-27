class Expense {
  final String id;
  final String category; // tea, drink, ice_cream, donation, food, other
  final String description;
  final double amount;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'description': description,
      'amount': amount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] ?? '',
      category: map['category'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  String get categoryDisplayName {
    switch (category) {
      case 'tea':
        return 'Tea';
      case 'drink':
        return 'Drink';
      case 'ice_cream':
        return 'Ice Cream';
      case 'donation':
        return 'Donation';
      case 'food':
        return 'Food';
      case 'other':
        return 'Other';
      default:
        return category;
    }
  }

  String get categoryIcon {
    switch (category) {
      case 'tea':
        return '☕';
      case 'drink':
        return '🥤';
      case 'ice_cream':
        return '🍦';
      case 'donation':
        return '💝';
      case 'food':
        return '🍽️';
      case 'other':
        return '📋';
      default:
        return '💰';
    }
  }
}
