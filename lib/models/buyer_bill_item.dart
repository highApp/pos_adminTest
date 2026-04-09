class BuyerBillItem {
  final String id;
  final String itemName;
  final double price;
  final String unit;
  final double quantity;
  /// Shown on the bill (line + summary).
  final double expense;
  /// Affects line total and stock cost but is not shown on the bill.
  final double hiddenItemExpense;
  /// Per-line share of bill-level manual expense (visible), by line total qty.
  final double distributedVisibleExpense;
  /// Per-line share of bill-level manual expense (hidden), by line total qty.
  final double distributedHiddenExpense;
  final double subtotal;
  final DateTime? date;
  /// Free quantity added to total (does not affect price)
  final double bonusQty;
  /// Pack size (qty per pack) - for edit restore
  final double packSize;
  /// Packing type (Box, Carton, etc.) - for edit restore
  final String? packingType;
  /// Category for new product creation when bill is saved
  final String? category;
  /// When the line creates a new product (no match in DB), these are applied at bill save.
  final double? newProductSalePrice;
  final double? newProductWholesalePrice;
  final double? newProductDozenPrice;
  final double? newProductBundlePrice;
  final int? newProductBundleSize;
  final double? newProductMinimumSalePrice;

  BuyerBillItem({
    required this.id,
    required this.itemName,
    required this.price,
    required this.unit,
    required this.quantity,
    required this.expense,
    this.hiddenItemExpense = 0,
    this.distributedVisibleExpense = 0,
    this.distributedHiddenExpense = 0,
    required this.subtotal,
    this.date,
    this.bonusQty = 0,
    this.packSize = 1,
    this.packingType,
    this.category,
    this.newProductSalePrice,
    this.newProductWholesalePrice,
    this.newProductDozenPrice,
    this.newProductBundlePrice,
    this.newProductBundleSize,
    this.newProductMinimumSalePrice,
  });

  /// All cost components layered on top of the buyer-facing line total.
  double get totalExpensesOnLine =>
      expense +
          hiddenItemExpense +
          distributedVisibleExpense +
          distributedHiddenExpense;

  /// Buyer-facing line total (tax-inclusive, before any expenses).
  double get buyerLineSubtotal => subtotal - totalExpensesOnLine;

  /// Expenses that should appear on the bill for this line.
  double get visibleExpensesOnLine => expense + distributedVisibleExpense;

  BuyerBillItem copyWith({
    String? id,
    String? itemName,
    double? price,
    String? unit,
    double? quantity,
    double? expense,
    double? hiddenItemExpense,
    double? distributedVisibleExpense,
    double? distributedHiddenExpense,
    double? subtotal,
    DateTime? date,
    double? bonusQty,
    double? packSize,
    String? packingType,
    String? category,
    double? newProductSalePrice,
    double? newProductWholesalePrice,
    double? newProductDozenPrice,
    double? newProductBundlePrice,
    int? newProductBundleSize,
    double? newProductMinimumSalePrice,
  }) {
    return BuyerBillItem(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      expense: expense ?? this.expense,
      hiddenItemExpense: hiddenItemExpense ?? this.hiddenItemExpense,
      distributedVisibleExpense:
      distributedVisibleExpense ?? this.distributedVisibleExpense,
      distributedHiddenExpense:
      distributedHiddenExpense ?? this.distributedHiddenExpense,
      subtotal: subtotal ?? this.subtotal,
      date: date ?? this.date,
      bonusQty: bonusQty ?? this.bonusQty,
      packSize: packSize ?? this.packSize,
      packingType: packingType ?? this.packingType,
      category: category ?? this.category,
      newProductSalePrice: newProductSalePrice ?? this.newProductSalePrice,
      newProductWholesalePrice:
      newProductWholesalePrice ?? this.newProductWholesalePrice,
      newProductDozenPrice: newProductDozenPrice ?? this.newProductDozenPrice,
      newProductBundlePrice:
      newProductBundlePrice ?? this.newProductBundlePrice,
      newProductBundleSize: newProductBundleSize ?? this.newProductBundleSize,
      newProductMinimumSalePrice:
      newProductMinimumSalePrice ?? this.newProductMinimumSalePrice,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemName': itemName,
      'price': price,
      'unit': unit,
      'quantity': quantity,
      'expense': expense,
      'hiddenItemExpense': hiddenItemExpense,
      'distributedVisibleExpense': distributedVisibleExpense,
      'distributedHiddenExpense': distributedHiddenExpense,
      'subtotal': subtotal,
      'date': date?.toIso8601String(),
      'bonusQty': bonusQty,
      'packSize': packSize,
      'packingType': packingType,
      'category': category,
      'newProductSalePrice': newProductSalePrice,
      'newProductWholesalePrice': newProductWholesalePrice,
      'newProductDozenPrice': newProductDozenPrice,
      'newProductBundlePrice': newProductBundlePrice,
      'newProductBundleSize': newProductBundleSize,
      'newProductMinimumSalePrice': newProductMinimumSalePrice,
    };
  }

  factory BuyerBillItem.fromMap(Map<String, dynamic> map) {
    return BuyerBillItem(
      id: map['id'] ?? '',
      itemName: map['itemName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      unit: map['unit'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      expense: (map['expense'] ?? 0).toDouble(),
      hiddenItemExpense: (map['hiddenItemExpense'] ?? 0).toDouble(),
      distributedVisibleExpense:
      (map['distributedVisibleExpense'] ?? 0).toDouble(),
      distributedHiddenExpense:
      (map['distributedHiddenExpense'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      date: map['date'] != null ? DateTime.parse(map['date']) : null,
      bonusQty: (map['bonusQty'] ?? 0).toDouble(),
      packSize: (map['packSize'] ?? 1).toDouble(),
      packingType: map['packingType'] as String?,
      category: map['category'] as String?,
      newProductSalePrice: (map['newProductSalePrice'] as num?)?.toDouble(),
      newProductWholesalePrice:
      (map['newProductWholesalePrice'] as num?)?.toDouble(),
      newProductDozenPrice: (map['newProductDozenPrice'] as num?)?.toDouble(),
      newProductBundlePrice:
      (map['newProductBundlePrice'] as num?)?.toDouble(),
      newProductBundleSize: (map['newProductBundleSize'] as num?)?.toInt(),
      newProductMinimumSalePrice:
      (map['newProductMinimumSalePrice'] as num?)?.toDouble(),
    );
  }
}
