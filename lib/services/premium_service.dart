import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PremiumService extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _rawIsPremium = false;
  DateTime? _expiresAt;

  /// True only while a purchase is on file AND (it never expires, or its
  /// expiry hasn't passed yet). A lapsed monthly/5-year plan reads as false
  /// here even though the underlying Firestore flag is still `true` — the
  /// raw flag is only cleared on an explicit setPremium(false) call.
  bool get isPremium {
    if (!_rawIsPremium) return false;
    final expiresAt = _expiresAt;
    if (expiresAt == null) return true;
    return expiresAt.isAfter(DateTime.now());
  }

  String? _listeningUid;

  void listen(String uid) {
    if (_listeningUid == uid) return;
    _listeningUid = uid;
    _db.collection('users').doc(uid).collection('meta').doc('premium').snapshots().listen((doc) {
      final data = doc.data();
      _rawIsPremium = data?['isPremium'] as bool? ?? false;
      final expiresAtTimestamp = data?['expiresAt'] as Timestamp?;
      _expiresAt = expiresAtTimestamp?.toDate();
      notifyListeners();
    });
  }

  /// [expiresAt] null means the plan never expires (lifetime). Pass a date
  /// for time-limited plans (5-year) or subscriptions (monthly) — for
  /// subscriptions, call this again on every renewal to push the date out.
  Future<void> setPremium(String uid, bool value, {String? plan, DateTime? expiresAt}) {
    return _db.collection('users').doc(uid).collection('meta').doc('premium').set({
      'isPremium': value,
      if (plan != null) 'plan': plan,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
