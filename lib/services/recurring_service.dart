import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';
import '../models/recurring_transaction.dart';
import 'firestore_service.dart';

class RecurringService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreService _firestoreService;

  RecurringService(this._firestoreService);

  CollectionReference<Map<String, dynamic>> _recurringRef(String uid) {
    return _db.collection('users').doc(uid).collection('recurring');
  }

  Stream<List<RecurringTransaction>> allRecurring(String uid, String accountId) {
    return _recurringRef(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map(RecurringTransaction.fromFirestore)
            .where((t) => t.accountId == accountId)
            .toList());
  }

  Future<void> createRecurring(String uid, RecurringTransaction template) {
    return _recurringRef(uid).add(template.toFirestore());
  }

  Future<void> setActive(String uid, String id, bool active) {
    return _recurringRef(uid).doc(id).update({'active': active});
  }

  Future<void> deleteRecurring(String uid, String id) {
    return _recurringRef(uid).doc(id).delete();
  }

  String _monthKey(DateTime month) => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  /// Generates this month's transaction for every active template (across all
  /// accounts) that hasn't already been generated for the current month and
  /// whose day has arrived.
  Future<void> processDueRecurring(String uid) async {
    final now = DateTime.now();
    final currentMonthKey = _monthKey(now);
    final snapshot = await _recurringRef(uid).where('active', isEqualTo: true).get();

    // Runs on every app launch, so it needs to stay fast even when several
    // templates are due at once (e.g. start of a new month) — one batched
    // commit instead of awaiting a pair of writes per template in sequence.
    final batch = _db.batch();
    var hasWrites = false;

    for (final doc in snapshot.docs) {
      final template = RecurringTransaction.fromFirestore(doc);
      if (template.lastGeneratedMonth == currentMonthKey) continue;
      if (now.day < template.dayOfMonth) continue;

      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final generatedDay = template.dayOfMonth.clamp(1, daysInMonth);

      final expense = Expense(
        id: '',
        amount: template.amount,
        category: template.category,
        date: DateTime(now.year, now.month, generatedDay),
        note: template.note,
        type: template.type,
        paymentMethod: template.paymentMethod,
        accountId: template.accountId,
        personName: template.personName,
        groupId: template.groupId,
      );
      batch.set(_firestoreService.newExpenseRef(uid), expense.toFirestore());
      batch.update(doc.reference, {'lastGeneratedMonth': currentMonthKey});
      hasWrites = true;
    }

    if (hasWrites) await batch.commit();
  }
}
