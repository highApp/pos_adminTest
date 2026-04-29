class BusinessReportStats {
  final double totalRevenue;
  final double totalBorrow;
  final double totalExpense;
  final double totalPaid;
  final double totalRecovery;

  // Profit split
  final double totalProfitReal;
  final double borrowProfitPending;
  final double totalProfitWithBorrow;

  const BusinessReportStats({
    required this.totalRevenue,
    required this.totalBorrow,
    required this.totalExpense,
    required this.totalPaid,
    required this.totalRecovery,
    required this.totalProfitReal,
    required this.borrowProfitPending,
    required this.totalProfitWithBorrow,
  });
}

