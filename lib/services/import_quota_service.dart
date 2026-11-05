import 'package:cloud_firestore/cloud_firestore.dart';

/// Free accounts can import a limited number of transactions each calendar month;
/// Premium has no limit. The month's count is kept with the user's other data so it
/// follows them to a new phone.
class ImportQuotaService {
  static const int freeMonthlyLimit = 25;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid).collection('meta').doc('importUsage');

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// How many free imports are left, given how many were used. Never below zero.
  static int remaining(int used) => (freeMonthlyLimit - used).clamp(0, freeMonthlyLimit);

  Future<int> usedThisMonth(String uid) async {
    try {
      final data = (await _doc(uid).get().timeout(const Duration(seconds: 6))).data();
      if (data == null || data['month'] != monthKey(DateTime.now())) return 0;
      return (data['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // If the count cannot be read, do not block the user.
      return 0;
    }
  }

  Future<void> record(String uid, int imported) async {
    try {
      final used = await usedThisMonth(uid);
      await _doc(uid).set({'month': monthKey(DateTime.now()), 'count': used + imported});
    } catch (_) {}
  }
}
