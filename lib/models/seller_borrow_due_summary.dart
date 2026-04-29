class SellerBorrowDueSummary {
  final String sellerId;
  final String sellerName;
  final double manualDue;
  final double posDue;

  double get totalDue => manualDue + posDue;

  const SellerBorrowDueSummary({
    required this.sellerId,
    required this.sellerName,
    required this.manualDue,
    required this.posDue,
  });
}

