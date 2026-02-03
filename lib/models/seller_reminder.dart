class SellerReminder {
  final String id;
  final String sellerId;
  final String message;
  final DateTime reminderDate;
  final bool isCompleted;
  final DateTime createdAt;

  SellerReminder({
    required this.id,
    required this.sellerId,
    required this.message,
    required this.reminderDate,
    this.isCompleted = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sellerId': sellerId,
      'message': message,
      'reminderDate': reminderDate.toIso8601String(),
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SellerReminder.fromMap(Map<String, dynamic> map) {
    return SellerReminder(
      id: map['id'] ?? '',
      sellerId: map['sellerId'] ?? '',
      message: map['message'] ?? '',
      reminderDate: map['reminderDate'] != null
          ? DateTime.parse(map['reminderDate'])
          : DateTime.now(),
      isCompleted: map['isCompleted'] ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  SellerReminder copyWith({
    String? id,
    String? sellerId,
    String? message,
    DateTime? reminderDate,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return SellerReminder(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      message: message ?? this.message,
      reminderDate: reminderDate ?? this.reminderDate,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
