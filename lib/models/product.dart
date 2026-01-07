class Product {
  final String id;
  final String? _name; // Internal field for backward compatibility with old data
  final Map<String, String>? names; // Language -> Name mapping (e.g., {'en': 'Product', 'ur': 'پروڈکٹ', 'ar': 'منتج'})
  final String? description;
  final double purchasePrice; // Buying/cost price
  final double salePrice; // Selling price
  final double? wholesalePrice; // Wholesale price (optional)
  final double stock; // Changed from int to double to support fractional stock
  final String unit; // Unit of measurement (kg, g, L, pieces, etc.)
  final double? value; // Value/size of product (e.g., 500 for 500g, 1 for 1L)
  final String? barcode;
  final String category;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    String? name,
    this.names,
    this.description,
    required this.purchasePrice,
    required this.salePrice,
    this.wholesalePrice,
    required this.stock,
    required this.unit,
    this.value,
    this.barcode,
    required this.category,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  }) : _name = name;

  // Getter for name with backward compatibility
  // Returns English name if available, otherwise first available name, otherwise old name field
  String get name {
    if (names != null && names!.isNotEmpty) {
      // Try to get English name first
      if (names!.containsKey('en') && names!['en']!.trim().isNotEmpty) {
        return names!['en']!;
      }
      // Otherwise return first available name
      return names!.values.firstWhere((n) => n.trim().isNotEmpty, orElse: () => names!.values.first);
    }
    // Fallback to old name field for backward compatibility
    return _name ?? '';
  }

  // Alias for name (for clarity)
  String get displayName => name;

  // Get name in specific language
  String? getName(String languageCode) {
    return names?[languageCode];
  }

  // Convert Product to Map for Firebase
  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'description': description,
      'purchasePrice': purchasePrice,
      'salePrice': salePrice,
      'wholesalePrice': wholesalePrice,
      'stock': stock,
      'unit': unit,
      'value': value,
      'barcode': barcode,
      'category': category,
      'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
    
    // Save names map if available, otherwise save name for backward compatibility
    if (names != null && names!.isNotEmpty) {
      map['names'] = names;
      // Also save English name as 'name' for backward compatibility
      if (names!.containsKey('en') && names!['en']!.trim().isNotEmpty) {
        map['name'] = names!['en'];
      } else {
        map['name'] = names!.values.firstWhere((n) => n.trim().isNotEmpty, orElse: () => '');
      }
    } else if (_name != null) {
      map['name'] = _name;
    }
    
    return map;
  }

  // Create Product from Firebase Map
  factory Product.fromMap(Map<String, dynamic> map) {
    // Handle backward compatibility: if old 'price' exists, use it for both
    final double purchasePriceValue = map['purchasePrice'] != null 
        ? (map['purchasePrice'] as num).toDouble()
        : (map['price'] ?? 0).toDouble();
    final double salePriceValue = map['salePrice'] != null
        ? (map['salePrice'] as num).toDouble()
        : (map['price'] ?? 0).toDouble();
    
    // Handle names: prefer names map, fallback to name field for backward compatibility
    Map<String, String>? namesMap;
    String? nameValue;
    
    if (map['names'] != null) {
      // New format with multiple names
      final namesData = map['names'];
      if (namesData is Map) {
        namesMap = Map<String, String>.from(
          namesData.map((key, value) => MapEntry(key.toString(), value.toString()))
        );
      }
    }
    
    // For backward compatibility, if no names map exists, use name field
    if (namesMap == null || namesMap.isEmpty) {
      nameValue = map['name']?.toString() ?? '';
    }
    
    return Product(
      id: map['id'] ?? '',
      name: nameValue,
      names: namesMap,
      description: map['description']?.toString(),
      purchasePrice: purchasePriceValue,
      salePrice: salePriceValue,
      wholesalePrice: map['wholesalePrice'] != null 
          ? (map['wholesalePrice'] as num).toDouble() 
          : null,
      stock: (map['stock'] ?? 0).toDouble(),
      unit: map['unit'] ?? 'pieces',
      value: map['value'] != null ? (map['value'] as num).toDouble() : null,
      barcode: map['barcode']?.toString(),
      category: map['category'] ?? 'General',
      imageUrl: map['imageUrl']?.toString(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  // Copy with method for updates
  Product copyWith({
    String? id,
    String? name,
    Map<String, String>? names,
    String? description,
    double? purchasePrice,
    double? salePrice,
    double? wholesalePrice,
    double? stock,
    String? unit,
    double? value,
    String? barcode,
    String? category,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this._name,
      names: names ?? this.names,
      description: description ?? this.description,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      value: value ?? this.value,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  // Helper method to calculate profit per item
  double get profitPerItem => salePrice - purchasePrice;
  
  // Helper method to calculate profit percentage
  double get profitPercentage => purchasePrice > 0 
      ? ((salePrice - purchasePrice) / purchasePrice) * 100 
      : 0;
  
  // Helper method to get formatted size (e.g., "500g", "1kg")
  String get formattedSize {
    if (value != null && value! > 0) {
      // Format the value to remove unnecessary decimals
      String valueStr = value! % 1 == 0 ? value!.toInt().toString() : value.toString();
      return '$valueStr$unit';
    }
    return '';
  }
}

