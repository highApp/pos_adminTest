import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service to reset Total Revenue, Revenue, Credit, and Recovery display to zero
/// by setting a "reset date". No data is deleted; the dashboard only counts data after this date.
class ResetDataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _settingsDoc = 'financial';

  /// Get the financial reset date. If set, dashboard shows only data after this date for
  /// Total Revenue, Revenue, Credit, Recovery. Returns null if never reset.
  Future<DateTime?> getFinancialResetDate() async {
    try {
      final doc = await _firestore.collection('app_settings').doc(_settingsDoc).get();
      if (!doc.exists) return null;
      final data = doc.data();
      final value = data?['resetDate'];
      if (value == null) return null;
      if (value is Timestamp) return (value as Timestamp).toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    } catch (e) {
      debugPrint('Error getting financial reset date: $e');
      return null;
    }
  }

  /// Set the financial reset date to [date]. Dashboard will only count data on or after this date
  /// for Total Revenue, Revenue, Credit, Recovery. No data is deleted.
  Future<void> setFinancialResetDate(DateTime date) async {
    await _firestore.collection('app_settings').doc(_settingsDoc).set({
      'resetDate': Timestamp.fromDate(date),
    }, SetOptions(merge: true));
    debugPrint('Financial reset date set to: $date');
  }

  /// Reset Total Revenue, Revenue, Credit, and Recovery to zero by setting reset date to now.
  /// No sales, orders, or any other data are deleted.
  Future<void> resetRevenueCreditRecovery() async {
    debugPrint('=== RESET REVENUE / CREDIT / RECOVERY (date only) - START ===');
    await setFinancialResetDate(DateTime.now());
    debugPrint('=== RESET REVENUE / CREDIT / RECOVERY - COMPLETE ===');
  }
}
