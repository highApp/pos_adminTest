import 'sale_item.dart';

enum SaleTypeEnum { regular, wholesale }

class Sale {
  final String id;
  final List<SaleItem> items;
  final double total;
  final double profit; // Total profit from the sale
  final double amountPaid;
  final double change;
  final DateTime createdAt;
  final String? customerName;
  final String paymentMethod;
  final double returnedAmount; // Total amount returned
  final bool isPartialReturn; // Whether this sale has partial returns
  final String? sellerId; // Optional seller ID
  final double recoveryBalance; // Amount recovered from existing due payments (when seller is selected and payment exceeds sale amount)
  final bool isBorrowPayment; // Whether this sale is a borrow payment (money received from paying back a borrow)
  final double creditUsed; // Amount of credit balance used from seller (tracked separately, NOT added to revenue)
  final String saleType; // 'regular' or 'wholesale'
  final String? description; // Optional description for the sale

  Sale({
    required this.id,
    required this.items,
    required this.total,
    this.profit = 0.0,
    required this.amountPaid,
    required this.change,
    required this.createdAt,
    this.customerName,
    this.paymentMethod = 'cash',
    this.returnedAmount = 0.0,
    this.isPartialReturn = false,
    this.sellerId,
    this.recoveryBalance = 0.0,
    this.isBorrowPayment = false,
    this.creditUsed = 0.0,
    this.saleType = 'regular',
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'profit': profit,
      'amountPaid': amountPaid,
      'change': change,
      'createdAt': createdAt.toIso8601String(),
      'customerName': customerName,
      'paymentMethod': paymentMethod,
      'returnedAmount': returnedAmount,
      'isPartialReturn': isPartialReturn,
      'sellerId': sellerId,
      'recoveryBalance': recoveryBalance,
      'isBorrowPayment': isBorrowPayment,
      'creditUsed': creditUsed,
      'saleType': saleType,
      'description': description,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] ?? '',
      items: (map['items'] as List<dynamic>?)
              ?.map((item) => SaleItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      total: (map['total'] ?? 0).toDouble(),
      profit: (map['profit'] ?? 0).toDouble(),
      amountPaid: (map['amountPaid'] ?? 0).toDouble(),
      change: (map['change'] ?? 0).toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      customerName: map['customerName'],
      paymentMethod: map['paymentMethod'] ?? 'cash',
      returnedAmount: (map['returnedAmount'] ?? 0).toDouble(),
      isPartialReturn: map['isPartialReturn'] ?? false,
      sellerId: map['sellerId'],
      recoveryBalance: (map['recoveryBalance'] ?? 0).toDouble(),
      isBorrowPayment: map['isBorrowPayment'] ?? false,
      creditUsed: (map['creditUsed'] ?? 0).toDouble(),
      saleType: map['saleType'] ?? 'regular',
      description: map['description'],
    );
  }
  
  // Get net total (total minus returned amount)
  double get netTotal => total - returnedAmount;
  
  // Calculate net profit (profit proportional to net total)
  double get netProfit {
    if (total == 0) return 0;
    // Profit reduces proportionally to the returned amount
    return profit * (netTotal / total);
  }
}

