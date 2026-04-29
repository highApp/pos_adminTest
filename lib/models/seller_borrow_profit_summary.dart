class SellerBorrowProfitSummary {
  final String sellerId;
  final String sellerName;
  final double borrowProfitPending;
  final double remainingDue;

  const SellerBorrowProfitSummary({
    required this.sellerId,
    required this.sellerName,
    required this.borrowProfitPending,
    required this.remainingDue,
  });
}

