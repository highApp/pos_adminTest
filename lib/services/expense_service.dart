import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';

class ExpenseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'expenses';

  // Add new expense
  Future<void> addExpense(Expense expense) async {
    await _firestore.collection(_collection).doc(expense.id).set(expense.toMap());
  }

  // Get all expenses stream
  Stream<List<Expense>> getExpensesStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Expense.fromMap(doc.data());
      }).toList();
    });
  }

  // Get expenses by date range
  Stream<List<Expense>> getExpensesByDateRange(DateTime startDate, DateTime endDate) {
    return _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Expense.fromMap(doc.data());
      }).toList();
    });
  }

  // Get total expenses by date range
  Future<double> getTotalExpensesByDateRange(DateTime startDate, DateTime endDate) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .get();

    double total = 0.0;
    for (var doc in snapshot.docs) {
      final expense = Expense.fromMap(doc.data());
      total += expense.amount;
    }

    return total;
  }

  // Get expenses by category
  Future<Map<String, double>> getExpensesByCategory(DateTime startDate, DateTime endDate) async {
    final snapshot = await _firestore
        .collection(_collection)
        .where('createdAt', isGreaterThanOrEqualTo: startDate.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endDate.toIso8601String())
        .get();

    Map<String, double> categoryTotals = {};
    for (var doc in snapshot.docs) {
      final expense = Expense.fromMap(doc.data());
      categoryTotals[expense.category] = (categoryTotals[expense.category] ?? 0) + expense.amount;
    }

    return categoryTotals;
  }

  // Update expense
  Future<void> updateExpense(Expense expense) async {
    await _firestore.collection(_collection).doc(expense.id).update(expense.toMap());
  }

  // Delete expense
  Future<void> deleteExpense(String expenseId) async {
    await _firestore.collection(_collection).doc(expenseId).delete();
  }
}
