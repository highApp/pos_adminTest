class Buyer {
  final String id;
  final String name;
  final String? phone;
  final String? location;
  final String? shopNo;
  final double? dueBalance;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Buyer({
    required this.id,
    required this.name,
    this.phone,
    this.location,
    this.shopNo,
    this.dueBalance,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'location': location,
      'shopNo': shopNo,
      'dueBalance': dueBalance,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory Buyer.fromMap(Map<String, dynamic> map) {
    return Buyer(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'],
      location: map['location'],
      shopNo: map['shopNo'],
      dueBalance: map['dueBalance'] != null ? (map['dueBalance'] as num).toDouble() : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : null,
    );
  }

  Buyer copyWith({
    String? id,
    String? name,
    String? phone,
    String? location,
    String? shopNo,
    double? dueBalance,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Buyer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      shopNo: shopNo ?? this.shopNo,
      dueBalance: dueBalance ?? this.dueBalance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
