import 'buyer_bill_item.dart';

class BuyerBill {
  final String id;
  final String buyerId;
  final String buyerName;
  final List<BuyerBillItem> items;
  final double total;
  final double totalExpense;
  final double finalPrice; // Total + Total Expense
  final double amountPaid;
  final double change;
  final DateTime createdAt;
  final String paymentMethod;
  final String? notes;
  final String? billNumber;

  BuyerBill({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.items,
    required this.total,
    required this.totalExpense,
    required this.finalPrice,
    required this.amountPaid,
    required this.change,
    required this.createdAt,
    this.paymentMethod = 'cash',
    this.notes,
    this.billNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'totalExpense': totalExpense,
      'finalPrice': finalPrice,
      'amountPaid': amountPaid,
      'change': change,
      'createdAt': createdAt.toIso8601String(),
      'paymentMethod': paymentMethod,
      'notes': notes,
      'billNumber': billNumber,
    };
  }

  factory BuyerBill.fromMap(Map<String, dynamic> map) {
    return BuyerBill(
      id: map['id'] ?? '',
      buyerId: map['buyerId'] ?? '',
      buyerName: map['buyerName'] ?? '',
      items: (map['items'] as List<dynamic>?)
              ?.map((item) => BuyerBillItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      total: (map['total'] ?? 0).toDouble(),
      totalExpense: (map['totalExpense'] ?? 0).toDouble(),
      finalPrice: (map['finalPrice'] ?? 0).toDouble(),
      amountPaid: (map['amountPaid'] ?? 0).toDouble(),
      change: (map['change'] ?? 0).toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      paymentMethod: map['paymentMethod'] ?? 'cash',
      notes: map['notes'],
      billNumber: map['billNumber'],
    );
  }
}
