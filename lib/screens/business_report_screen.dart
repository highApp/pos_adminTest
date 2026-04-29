import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_report_stats.dart';
import '../models/borrow_totals_breakdown.dart';
import '../models/seller_borrow_profit_summary.dart';
import '../models/seller_real_profit_summary.dart';
import '../services/business_report_stats_service.dart';

class BusinessReportScreen extends StatefulWidget {
  const BusinessReportScreen({super.key});

  @override
  State<BusinessReportScreen> createState() => _BusinessReportScreenState();
}

enum _ReportRangeMode { weekly, monthly, custom }

class _BusinessReportScreenState extends State<BusinessReportScreen> {
  final _statsService = BusinessReportStatsService();
  final _currency = NumberFormat.currency(symbol: 'Rs. ');

  _ReportRangeMode _mode = _ReportRangeMode.monthly;

  DateTime _anchorDate = DateTime.now();
  DateTime _customStart = DateTime.now();
  DateTime _customEnd = DateTime.now();

  bool _showBreakdown = true;

  Future<BusinessReportStats>? _totalsFuture;
  List<({DateTime start, DateTime end, String label})> _bucketRanges = const [];
  List<Future<BusinessReportStats>> _bucketFutures = const [];

  void _refreshFutures() {
    final totalRange = _getTotalRange();
    final buckets = _showBreakdown ? _buildBuckets() : const <({DateTime start, DateTime end, String label})>[];

    setState(() {
      _totalsFuture =
          _statsService.calculateForRange(startDate: totalRange.start, endDate: totalRange.end);
      _bucketRanges = buckets;
      _bucketFutures = buckets
          .map((b) =>
              _statsService.calculateForRange(startDate: b.start, endDate: b.end))
          .toList(growable: false);
    });
  }

  void _showBorrowProfitPendingSellersDialog({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final future = _statsService.getBorrowProfitPendingBySellerForRange(
      startDate: startDate,
      endDate: endDate,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Borrow Profit (Pending) - By Seller'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: FutureBuilder<List<SellerBorrowProfitSummary>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                final items = snapshot.data ?? const <SellerBorrowProfitSummary>[];
                if (items.isEmpty) {
                  return const Text('No sellers found for this date range.');
                }
                const pageSize = 20;
                var shownCount = items.length < pageSize ? items.length : pageSize;

                return StatefulBuilder(
                  builder: (context, setState) {
                    final shown = items.take(shownCount).toList(growable: false);
                    final canLoadMore = shownCount < items.length;

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = shown[i];
                              return ListTile(
                                dense: true,
                                title: Text(item.sellerName),
                                subtitle: Text(
                                  'Remaining due: ${_currency.format(item.remainingDue)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  _currency.format(item.borrowProfitPending),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              );
                            },
                          ),
                        ),
                        if (canLoadMore)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  shownCount = (shownCount + pageSize) > items.length
                                      ? items.length
                                      : (shownCount + pageSize);
                                });
                              },
                              child: const Text('Load more'),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showBorrowTotalsBreakdownDialog({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final future = _statsService.getBorrowTotalsBreakdownForRange(
      startDate: startDate,
      endDate: endDate,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Total Borrow - Breakdown'),
          content: SizedBox(
            width: 520,
            height: 520,
            child: FutureBuilder<BorrowTotalsBreakdown>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return Text('Error: ${snapshot.error}');
                }

                final d = snapshot.data!;
                if (d.sellers.isEmpty) {
                  return const Text('No unpaid borrow dues found for this date range.');
                }

                const pageSize = 20;
                var shownCount = d.sellers.length < pageSize ? d.sellers.length : pageSize;

                return StatefulBuilder(
                  builder: (context, setState) {
                    final shown = d.sellers.take(shownCount).toList(growable: false);
                    final canLoadMore = shownCount < d.sellers.length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            _BreakdownChip(
                              label: 'Seller Due (Manual)',
                              value: _currency.format(d.sellerDueManual),
                            ),
                            _BreakdownChip(
                              label: 'Seller Due (POS)',
                              value: _currency.format(d.sellerDuePos),
                            ),
                            _BreakdownChip(
                              label: 'Borrow Book (Unpaid Borrowed)',
                              value: _currency.format(d.borrowBookBorrowed),
                            ),
                            _BreakdownChip(
                              label: 'Repayments In Period',
                              value: _currency.format(d.repaymentsInPeriod),
                            ),
                            _BreakdownChip(
                              label: 'Net Total Borrow (After repayments)',
                              value: _currency.format(d.netBorrow),
                              primary: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Sellers (remaining due):',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.separated(
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = shown[i];
                              return ListTile(
                                dense: true,
                                title: Text(item.sellerName),
                                subtitle: Text(
                                  'Manual: ${_currency.format(item.manualDue)}  |  POS: ${_currency.format(item.posDue)}',
                                ),
                                trailing: Text(
                                  _currency.format(item.totalDue),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              );
                            },
                          ),
                        ),
                        if (canLoadMore)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  shownCount = (shownCount + pageSize) > d.sellers.length
                                      ? d.sellers.length
                                      : (shownCount + pageSize);
                                });
                              },
                              child: const Text('Load more'),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showRealProfitSellersDialog({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final future = _statsService.getRealProfitBySellerForRange(
      startDate: startDate,
      endDate: endDate,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Real Profit - By Seller'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: FutureBuilder<List<SellerRealProfitSummary>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                final items = snapshot.data ?? const <SellerRealProfitSummary>[];
                if (items.isEmpty) {
                  return const Text('No sellers found for this date range.');
                }
                const pageSize = 20;
                var shownCount = items.length < pageSize ? items.length : pageSize;

                return StatefulBuilder(
                  builder: (context, setState) {
                    final shown = items.take(shownCount).toList(growable: false);
                    final canLoadMore = shownCount < items.length;
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = shown[i];
                              return ListTile(
                                dense: true,
                                title: Text(item.sellerName),
                                trailing: Text(
                                  _currency.format(item.realProfit),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              );
                            },
                          ),
                        ),
                        if (canLoadMore)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  shownCount = (shownCount + pageSize) > items.length
                                      ? items.length
                                      : (shownCount + pageSize);
                                });
                              },
                              child: const Text('Load more'),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshFutures();
  }

  /// Returns bucket ranges for breakdown.
  List<({DateTime start, DateTime end, String label})> _buildBuckets() {
    if (_mode == _ReportRangeMode.weekly) {
      final d = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day);
      // Week starts on Monday to match common business expectations.
      final weekday = d.weekday; // Mon=1..Sun=7
      final monday = d.subtract(Duration(days: weekday - 1));
      final buckets = <({DateTime start, DateTime end, String label})>[];
      for (int i = 0; i < 7; i++) {
        final day = monday.add(Duration(days: i));
        final start = DateTime(day.year, day.month, day.day);
        final end = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
        buckets.add((
          start: start,
          end: end,
          label: DateFormat('MMM d').format(day),
        ));
      }
      return buckets;
    }

    if (_mode == _ReportRangeMode.monthly) {
      final a = DateTime(_anchorDate.year, _anchorDate.month, 1);
      final monthStart = a;
      final nextMonth = DateTime(a.year, a.month + 1, 1);
      final monthEnd = nextMonth.subtract(const Duration(days: 1));

      // Split month into week buckets (Mon..Sun) clipped to month bounds.
      final firstWeekday = monthStart.weekday;
      final mondayOfFirst = monthStart.subtract(Duration(days: firstWeekday - 1));
      final lastWeekday = monthEnd.weekday;
      final mondayOfLast = monthEnd.subtract(Duration(days: lastWeekday - 1));

      final buckets = <({DateTime start, DateTime end, String label})>[];
      for (DateTime monday = mondayOfFirst;
          !monday.isAfter(mondayOfLast);
          monday = monday.add(const Duration(days: 7))) {
        final start = DateTime(
          monday.year,
          monday.month,
          monday.day,
        );
        final endDay = monday.add(const Duration(days: 6));
        final clippedStart = start.isBefore(monthStart) ? monthStart : start;
        final clippedEnd = endDay.isAfter(monthEnd) ? monthEnd : endDay;
        final bucketStart = DateTime(
          clippedStart.year,
          clippedStart.month,
          clippedStart.day,
        );
        final bucketEnd = DateTime(
          clippedEnd.year,
          clippedEnd.month,
          clippedEnd.day,
          23,
          59,
          59,
          999,
        );
        buckets.add((
          start: bucketStart,
          end: bucketEnd,
          label: '${DateFormat('MMM d').format(clippedStart)} - ${DateFormat('MMM d').format(clippedEnd)}',
        ));
      }
      return buckets;
    }

    // custom
    final start = DateTime(_customStart.year, _customStart.month, _customStart.day);
    final end = DateTime(_customEnd.year, _customEnd.month, _customEnd.day, 23, 59, 59, 999);
    if (end.isBefore(start)) return [];

    // Month-by-month buckets for custom ranges.
    final buckets = <({DateTime start, DateTime end, String label})>[];
    DateTime cursor = DateTime(start.year, start.month, 1);
    while (cursor.isBefore(end) || cursor.isAtSameMomentAs(end)) {
      final nextMonth = DateTime(cursor.year, cursor.month + 1, 1);
      final monthEndDay = nextMonth.subtract(const Duration(days: 1));
      final bucketStart = start.isAfter(cursor) ? start : cursor;
      final bucketEnd = monthEndDay.isBefore(end) ? monthEndDay : end;

      buckets.add((
        start: DateTime(bucketStart.year, bucketStart.month, bucketStart.day),
        end: DateTime(bucketEnd.year, bucketEnd.month, bucketEnd.day, 23, 59, 59, 999),
        label: DateFormat('MMM yyyy').format(cursor),
      ));

      cursor = nextMonth;
    }
    return buckets;
  }

  ({DateTime start, DateTime end}) _getTotalRange() {
    if (_mode == _ReportRangeMode.weekly) {
      final d = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day);
      final weekday = d.weekday;
      final monday = d.subtract(Duration(days: weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      return (
        start: DateTime(monday.year, monday.month, monday.day),
        end: DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999),
      );
    }
    if (_mode == _ReportRangeMode.monthly) {
      final monthStart = DateTime(_anchorDate.year, _anchorDate.month, 1);
      final nextMonth = DateTime(_anchorDate.year, _anchorDate.month + 1, 1);
      final monthEnd = nextMonth.subtract(const Duration(days: 1));
      return (
        start: monthStart,
        end: DateTime(monthEnd.year, monthEnd.month, monthEnd.day, 23, 59, 59, 999),
      );
    }

    final start = DateTime(_customStart.year, _customStart.month, _customStart.day);
    final end = DateTime(_customEnd.year, _customEnd.month, _customEnd.day, 23, 59, 59, 999);
    return (start: start, end: end);
  }

  Future<void> _pickAnchorDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _anchorDate = picked);
    _refreshFutures();
  }

  Future<void> _pickCustomStart(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStart,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _customStart = picked);
    _refreshFutures();
  }

  Future<void> _pickCustomEnd(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEnd,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _customEnd = picked);
    _refreshFutures();
  }

  @override
  Widget build(BuildContext context) {
    final totalRange = _getTotalRange();
    final buckets = _bucketRanges;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Report'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refreshFutures();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filter header
              Row(
                children: [
                  const Text('Range: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  DropdownButton<_ReportRangeMode>(
                    value: _mode,
                    items: const [
                      DropdownMenuItem(value: _ReportRangeMode.weekly, child: Text('Weekly')),
                      DropdownMenuItem(value: _ReportRangeMode.monthly, child: Text('Monthly')),
                      DropdownMenuItem(value: _ReportRangeMode.custom, child: Text('Custom')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      _mode = v;
                      _refreshFutures();
                    },
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Text('Breakdown', style: TextStyle(fontWeight: FontWeight.w600)),
                      Switch(
                        value: _showBreakdown,
                        onChanged: (v) {
                          _showBreakdown = v;
                          _refreshFutures();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_mode == _ReportRangeMode.weekly || _mode == _ReportRangeMode.monthly) ...[
                Text(
                  _mode == _ReportRangeMode.weekly
                      ? 'Pick a day (week starts Monday)'
                      : 'Pick a date (month view)',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickAnchorDate(context),
                      icon: const Icon(Icons.date_range),
                      label: Text(DateFormat('MMM d, yyyy').format(_anchorDate)),
                    ),
                  ],
                ),
              ],
              if (_mode == _ReportRangeMode.custom) ...[
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickCustomStart(context),
                      icon: const Icon(Icons.calendar_month),
                      label: Text(DateFormat('MMM d, yyyy').format(_customStart)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _pickCustomEnd(context),
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(DateFormat('MMM d, yyyy').format(_customEnd)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Totals
              FutureBuilder<BusinessReportStats>(
                future: _totalsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Text('Error: ${snapshot.error}');
                  }
                  final stats = snapshot.data!;
                  return _TotalsCard(
                    currency: _currency,
                    stats: stats,
                    title: 'Totals (${DateFormat('MMM d').format(totalRange.start)} - ${DateFormat('MMM d').format(totalRange.end)})',
                    onTotalBorrowTap: () => _showBorrowTotalsBreakdownDialog(
                      startDate: totalRange.start,
                      endDate: totalRange.end,
                    ),
                    onRealProfitTap: () => _showRealProfitSellersDialog(
                      startDate: totalRange.start,
                      endDate: totalRange.end,
                    ),
                    onBorrowProfitPendingTap: () => _showBorrowProfitPendingSellersDialog(
                      startDate: totalRange.start,
                      endDate: totalRange.end,
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Breakdown
              if (_showBreakdown)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mode == _ReportRangeMode.custom
                          ? 'Month breakdown'
                          : (_mode == _ReportRangeMode.weekly ? 'Day breakdown' : 'Week breakdown'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(buckets.length, (i) {
                      final b = buckets[i];
                      return FutureBuilder<BusinessReportStats>(
                        future: _bucketFutures[i],
                        builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            if (snap.hasError || snap.data == null) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('Error: ${snap.error}'),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _TotalsCard(
                                currency: _currency,
                                stats: snap.data!,
                                title: b.label,
                                compact: true,
                                onTotalBorrowTap: () => _showBorrowTotalsBreakdownDialog(
                                  startDate: b.start,
                                  endDate: b.end,
                                ),
                                onRealProfitTap: () => _showRealProfitSellersDialog(
                                  startDate: b.start,
                                  endDate: b.end,
                                ),
                                onBorrowProfitPendingTap: () =>
                                    _showBorrowProfitPendingSellersDialog(
                                  startDate: b.start,
                                  endDate: b.end,
                                ),
                              ),
                            );
                          },
                      );
                    }),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final NumberFormat currency;
  final BusinessReportStats stats;
  final String title;
  final bool compact;
  final VoidCallback? onTotalBorrowTap;
  final VoidCallback? onRealProfitTap;
  final VoidCallback? onBorrowProfitPendingTap;

  const _TotalsCard({
    required this.currency,
    required this.stats,
    required this.title,
    this.compact = false,
    this.onTotalBorrowTap,
    this.onRealProfitTap,
    this.onBorrowProfitPendingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (!compact) const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Metric(currency: currency, label: 'Total Revenue', value: stats.totalRevenue),
              _Metric(
                currency: currency,
                label: 'Total Borrow',
                value: stats.totalBorrow,
                onTap: onTotalBorrowTap,
              ),
              _Metric(currency: currency, label: 'Total Recovery', value: stats.totalRecovery),
              _Metric(currency: currency, label: 'Total Paid', value: stats.totalPaid),
              _Metric(currency: currency, label: 'Total Expense', value: stats.totalExpense),
              _Metric(
                currency: currency,
                label: 'Real Profit',
                value: stats.totalProfitReal,
                onTap: onRealProfitTap,
              ),
              _Metric(
                currency: currency,
                label: 'Borrow Profit (Pending)',
                value: stats.borrowProfitPending,
                onTap: onBorrowProfitPendingTap,
              ),
              _Metric(currency: currency, label: 'Total Profit (With Borrow)', value: stats.totalProfitWithBorrow),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final NumberFormat currency;
  final String label;
  final double value;
  final VoidCallback? onTap;

  const _Metric({
    required this.currency,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: interactive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              currency.format(value),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: interactive ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownChip extends StatelessWidget {
  final String label;
  final String value;
  final bool primary;

  const _BreakdownChip({
    required this.label,
    required this.value,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: primary
            ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: primary
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

