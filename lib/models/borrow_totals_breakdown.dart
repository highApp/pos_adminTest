import '../models/seller_borrow_due_summary.dart';

class BorrowTotalsBreakdown {
  final double sellerDueManual;
  final double sellerDuePos;
  final double sellerDueTotal;

  /// Borrow book: unpaid rows where type == 'borrowed'
  final double borrowBookBorrowed;

  /// Recovery applied to old dues within the selected period
  final double repaymentsInPeriod;

  /// dashboard math: (sellerDueTotal + borrowBookBorrowed - repaymentsInPeriod)
  /// clamped to >= 0
  final double netBorrow;

  final List<SellerBorrowDueSummary> sellers;

  const BorrowTotalsBreakdown({
    required this.sellerDueManual,
    required this.sellerDuePos,
    required this.sellerDueTotal,
    required this.borrowBookBorrowed,
    required this.repaymentsInPeriod,
    required this.netBorrow,
    required this.sellers,
  });
}

