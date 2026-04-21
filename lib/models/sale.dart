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
  /// Seller's total due balance before this sale (for receipt: Previous Due / Remaining Balance).
  final double existingDueTotalAtSale;

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
    this.existingDueTotalAtSale = 0.0,
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
      'existingDueTotalAtSale': existingDueTotalAtSale,
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
      existingDueTotalAtSale: (map['existingDueTotalAtSale'] ?? 0).toDouble(),
    );
  }
  
  // Get net total (total minus returned amount)
  double get netTotal => total - returnedAmount;

  /// True when every line has a stored cost so we can compute net profit from remaining qty exactly.
  bool get _allItemsHavePurchasePrice =>
      items.isNotEmpty && items.every((i) => i.purchasePrice != null);

  // Net profit after returns: exact margin on **remaining** quantity when cost was saved per line;
  // otherwise proportional (legacy sales without purchasePrice on items).
  double get netProfit {
    if (isBorrowPayment) return 0.0;
    if (returnedAmount <= 0) return profit;
    if (_allItemsHavePurchasePrice) {
      final sum = items.fold<double>(
        0.0,
        (s, i) =>
            s + (i.price - (i.purchasePrice ?? 0)) * i.remainingQuantity,
      );
      return sum < 0 ? 0.0 : sum;
    }
    if (total == 0) return 0;
    return profit * (netTotal / total);
  }

  /// Cash-like POS revenue used on the dashboard (excludes seller credit, change,
  /// recovery, and the cash-valued slice of returns). Borrow payments: use 0.
  /// Manual “Manual Payment” dues entries (total 0) are excluded from POS revenue.
  double get dashboardPosCashRevenue {
    if (isBorrowPayment) return 0.0;
    final isManualPaymentSale =
        total == 0 && (customerName?.startsWith('Manual Payment') ?? false);
    if (isManualPaymentSale) return 0.0;
    final cashPaid = amountPaid - recoveryBalance;
    final totalPaid = cashPaid + creditUsed;
    double cashPortionOfReturn = 0.0;
    if (returnedAmount > 0 && totalPaid > 0) {
      cashPortionOfReturn = returnedAmount * (cashPaid / totalPaid);
    }
    return amountPaid - recoveryBalance - change - cashPortionOfReturn;
  }
}

extension SaleItemNetLineProfit on SaleItem {
  /// Net profit on **remaining** (not returned) quantity: \((price − cost)×rem\).
  /// If [SaleItem.purchasePrice] is null (old sales), uses this line’s share of [sale].netProfit.
  double netLineProfit(Sale sale) {
    final rem = remainingQuantity;
    if (rem <= 0) return 0.0;
    final pp = purchasePrice;
    if (pp != null) {
      return (price - pp) * rem;
    }
    final netTotal = sale.netTotal;
    if (netTotal <= 0 || sale.isBorrowPayment) return 0.0;
    return sale.netProfit * (remainingSubtotal / netTotal);
  }
}

