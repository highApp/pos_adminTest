class BalanceEntry {
  final String id;
  final double amount;
  final String? description;
  final DateTime date;
  final DateTime createdAt;

  BalanceEntry({
    required this.id,
    required this.amount,
    this.description,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'description': description,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory BalanceEntry.fromMap(Map<String, dynamic> map) {
    return BalanceEntry(
      id: map['id'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      description: map['description'],
      date: map['date'] != null
          ? DateTime.parse(map['date'])
          : DateTime.now(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
