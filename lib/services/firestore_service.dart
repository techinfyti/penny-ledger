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

  /// A fresh document reference for a new expense, for callers that need to
  /// batch multiple writes together (see RecurringService.processDueRecurring)
  /// instead of awaiting addExpense one at a time.
  DocumentReference<Map<String, dynamic>> newExpenseRef(String uid) {
    return _expensesRef(uid).doc();
  }

  /// Writes many expenses in batches (Firestore allows 500 operations per batch).
  Future<void> addExpenses(String uid, List<Expense> expenses) async {
    const chunkSize = 400;
    for (var i = 0; i < expenses.length; i += chunkSize) {
      final batch = _db.batch();
      for (final expense in expenses.skip(i).take(chunkSize)) {
        batch.set(_expensesRef(uid).doc(), expense.toFirestore());
      }
      await batch.commit();
    }
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
    // Filtering by accountId in Firestore (rather than fetching the global
    // top-`limit` and filtering client-side) matters once a user has more
    // than one account: the old client-side filter could silently return
    // fewer than `limit` results — or none — for a less-active account,
    // since its documents might not even be among the top 200 across all
    // accounts. Requires a composite index on (accountId, date).
    return _expensesRef(uid)
        .where('accountId', isEqualTo: accountId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Expense.fromFirestore).toList());
  }
}
