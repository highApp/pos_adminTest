class Seller {
  final String id;
  final String name;
  final String? code;
  final String? phone;
  final String? location;
  final String? reference;
  final String? passwordHash;
  final DateTime createdAt;
  final bool isActive;

  Seller({
    required this.id,
    required this.name,
    this.code,
    this.phone,
    this.location,
    this.reference,
    this.passwordHash,
    required this.createdAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'phone': phone,
      'location': location,
      'reference': reference,
      'passwordHash': passwordHash,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory Seller.fromMap(Map<String, dynamic> map) {
    return Seller(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      code: map['code'],
      phone: map['phone'],
      location: map['location'],
      reference: map['reference'],
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
    String? code,
    String? phone,
    String? location,
    String? reference,
    String? passwordHash,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Seller(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      reference: reference ?? this.reference,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

