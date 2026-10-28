import 'package:cloud_firestore/cloud_firestore.dart';

class BudgetService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _categoryBudgetDoc(String uid, String accountId, DateTime month) {
    return _db.collection('users').doc(uid).collection('budgets').doc('${accountId}_${_monthKey(month)}');
  }

  /// Per-category limits for the given account and month, keyed by category name.
  Stream<Map<String, double>> categoryLimitsForMonth(String uid, String accountId, DateTime month) {
    return _categoryBudgetDoc(uid, accountId, month).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return {};
      final limits = <String, double>{};
      data.forEach((key, value) {
        if (key == 'alerts') return;
        if (value is num) limits[key] = value.toDouble();
      });
      return limits;
    });
  }

  Future<void> setCategoryLimit(String uid, String accountId, DateTime month, String category, double limit) async {
    await _categoryBudgetDoc(uid, accountId, month).set({category: limit}, SetOptions(merge: true));
  }

  Future<void> clearCategoryLimit(String uid, String accountId, DateTime month, String category) async {
    await _categoryBudgetDoc(uid, accountId, month).update({category: FieldValue.delete()});
  }

  /// Copies every category limit from one month into another, keeping any
  /// limit already set in the target month. Returns how many were copied.
  Future<int> copyLimits(String uid, String accountId, DateTime from, DateTime to) async {
    final source = await _categoryBudgetDoc(uid, accountId, from).get();
    final target = await _categoryBudgetDoc(uid, accountId, to).get();
    final existing = target.data() ?? {};
    final toCopy = <String, double>{};
    (source.data() ?? {}).forEach((key, value) {
      if (key == 'alerts' || value is! num || value <= 0) return;
      final current = existing[key];
      if (current is num && current > 0) return;
      toCopy[key] = value.toDouble();
    });
    if (toCopy.isEmpty) return 0;
    await _categoryBudgetDoc(uid, accountId, to).set(toCopy, SetOptions(merge: true));
    return toCopy.length;
  }

  Future<double?> categoryLimitOnce(String uid, String accountId, DateTime month, String category) async {
    final doc = await _categoryBudgetDoc(uid, accountId, month).get();
    final value = doc.data()?[category];
    return (value as num?)?.toDouble();
  }

  /// Highest alert threshold (80 or 100) already notified for this category
  /// this month, so we don't repeat the same alert on every transaction.
  Future<int?> alertedThreshold(String uid, String accountId, DateTime month, String category) async {
    final doc = await _categoryBudgetDoc(uid, accountId, month).get();
    final alerts = doc.data()?['alerts'] as Map<String, dynamic>?;
    return (alerts?[category] as num?)?.toInt();
  }

  Future<void> setAlertedThreshold(String uid, String accountId, DateTime month, String category, int threshold) async {
    await _categoryBudgetDoc(uid, accountId, month).set({
      'alerts': {category: threshold},
    }, SetOptions(merge: true));
  }

  String _monthKey(DateTime month) => '${month.year}-${month.month.toString().padLeft(2, '0')}';
}
