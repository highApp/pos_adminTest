import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/seller_reminder.dart';

class SellerReminderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'seller_reminders';

  // Add reminder
  Future<void> addReminder(SellerReminder reminder) async {
    await _firestore
        .collection(_collection)
        .doc(reminder.id)
        .set(reminder.toMap());
  }

  // Update reminder
  Future<void> updateReminder(SellerReminder reminder) async {
    await _firestore
        .collection(_collection)
        .doc(reminder.id)
        .update(reminder.toMap());
  }

  // Delete reminder
  Future<void> deleteReminder(String reminderId) async {
    await _firestore.collection(_collection).doc(reminderId).delete();
  }

  // Get reminders stream for a seller
  Stream<List<SellerReminder>> getRemindersForSellerStream(String sellerId) {
    return _firestore
        .collection(_collection)
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => SellerReminder.fromMap(doc.data()))
          .toList()
        ..sort((a, b) => b.reminderDate.compareTo(a.reminderDate));
    });
  }

  // Get active reminders (not completed, date is today or in future)
  // Real-time: computes dates inside map so day rollover is handled correctly
  Stream<List<SellerReminder>> getActiveRemindersStream() {
    return _firestore
        .collection(_collection)
        .where('isCompleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      return snapshot.docs
          .map((doc) => SellerReminder.fromMap(doc.data()))
          .where((r) =>
              r.reminderDate.isAfter(todayStart) ||
              _isSameDay(r.reminderDate, todayStart))
          .toList()
        ..sort((a, b) => a.reminderDate.compareTo(b.reminderDate));
    });
  }

  // Get reminders due today (for banner)
  // Real-time: computes dates inside map so day rollover is handled correctly
  Stream<List<SellerReminder>> getRemindersDueTodayStream() {
    return _firestore
        .collection(_collection)
        .where('isCompleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      return snapshot.docs
          .map((doc) => SellerReminder.fromMap(doc.data()))
          .where((r) =>
              !r.reminderDate.isBefore(todayStart) &&
              r.reminderDate.isBefore(todayEnd))
          .toList()
        ..sort((a, b) => a.reminderDate.compareTo(b.reminderDate));
    });
  }

  // Get upcoming reminders (reminderDate is after today)
  Stream<List<SellerReminder>> getUpcomingRemindersStream() {
    return _firestore
        .collection(_collection)
        .where('isCompleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return snapshot.docs
          .map((doc) => SellerReminder.fromMap(doc.data()))
          .where((r) => r.reminderDate.isAfter(todayEnd))
          .toList()
        ..sort((a, b) => a.reminderDate.compareTo(b.reminderDate));
    });
  }

  // Get overdue reminders (reminderDate has passed, not completed)
  // For real-time alerts when reminders become due
  Stream<List<SellerReminder>> getOverdueRemindersStream() {
    return _firestore
        .collection(_collection)
        .where('isCompleted', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .map((doc) => SellerReminder.fromMap(doc.data()))
          .where((r) => r.reminderDate.isBefore(now))
          .toList()
        ..sort((a, b) => a.reminderDate.compareTo(b.reminderDate));
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // Create a new reminder
  Future<SellerReminder> createReminder({
    required String sellerId,
    required String message,
    required DateTime reminderDate,
  }) async {
    final reminder = SellerReminder(
      id: const Uuid().v4(),
      sellerId: sellerId,
      message: message,
      reminderDate: reminderDate,
      createdAt: DateTime.now(),
    );
    await addReminder(reminder);
    return reminder;
  }
}
