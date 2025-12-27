class Seller {
  final String id;
  final String name;
  final String? phone;
  final String? location;
  final String? passwordHash;
  final DateTime createdAt;
  final bool isActive;

  Seller({
    required this.id,
    required this.name,
    this.phone,
    this.location,
    this.passwordHash,
    required this.createdAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'location': location,
      'passwordHash': passwordHash,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory Seller.fromMap(Map<String, dynamic> map) {
    return Seller(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'],
      location: map['location'],
      passwordHash: map['passwordHash'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      isActive: map['isActive'] ?? true,
    );
  }

  Seller copyWith({
    String? id,
    String? name,
    String? phone,
    String? location,
    String? passwordHash,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Seller(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

