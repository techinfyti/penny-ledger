import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _expensesRef(String uid) {
    return _db.collection('users').doc(uid).collection('expenses');
  }

  Future<void> addExpense(String uid, Expense expense) {
    return _expensesRef(uid).add(expense.toFirestore());
  }

  Future<void> updateExpense(String uid, Expense expense) {
    return _expensesRef(uid).doc(expense.id).update(expense.toFirestore());
  }

  Future<void> deleteExpense(String uid, String expenseId) {
    return _expensesRef(uid).doc(expenseId).delete();
  }

  Stream<List<Expense>> expensesForRange(
    String uid,
    String accountId,
    DateTime start,
    DateTime end,
  ) {
    return _expensesRef(uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map(Expense.fromFirestore)
            .where((e) => e.accountId == accountId)
            .toList());
  }

  Stream<List<Expense>> expensesForDay(String uid, String accountId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return expensesForRange(uid, accountId, start, end);
  }

  Stream<List<Expense>> expensesForMonth(String uid, String accountId, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return expensesForRange(uid, accountId, start, end);
  }

  Stream<List<Expense>> expensesForYear(String uid, String accountId, int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    return expensesForRange(uid, accountId, start, end);
  }

  Stream<List<Expense>> allExpenses(String uid, String accountId, {int limit = 200}) {
    return _expensesRef(uid)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(Expense.fromFirestore)
            .where((e) => e.accountId == accountId)
            .toList());
  }
}
