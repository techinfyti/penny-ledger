import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';

class AccountService extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _prefsKey = 'current_account_id';

  String _currentAccountId = defaultAccountId;
  String get currentAccountId => _currentAccountId;

  Future<void> loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    _currentAccountId = prefs.getString(_prefsKey) ?? defaultAccountId;
    notifyListeners();
  }

  Future<void> setCurrentAccount(String accountId) async {
    if (_currentAccountId == accountId) return;
    _currentAccountId = accountId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, accountId);
    notifyListeners();
  }

  CollectionReference<Map<String, dynamic>> _accountsRef(String uid) {
    return _db.collection('users').doc(uid).collection('accounts');
  }

  // One underlying Firestore listener per uid, shared across every caller.
  // accountsFor() wraps it in Stream.multi() so a listener that subscribes
  // after the first snapshot already arrived is replayed the latest value
  // immediately instead of sitting empty until the next Firestore write.
  final Map<String, Stream<List<Account>>> _broadcast = {};
  final Map<String, List<Account>> _latest = {};

  Stream<List<Account>> accountsFor(String uid) {
    _broadcast.putIfAbsent(uid, () {
      final controller = StreamController<List<Account>>.broadcast();
      _accountsRef(uid).orderBy('createdAt').snapshots().listen((snap) {
        final list = snap.docs.map(Account.fromFirestore).toList();
        _latest[uid] = list;
        controller.add(list);
      });
      return controller.stream;
    });

    return Stream<List<Account>>.multi((controller) {
      final cached = _latest[uid];
      if (cached != null) controller.add(cached);
      final sub = _broadcast[uid]!.listen(controller.add, onError: controller.addError, onDone: controller.close);
      controller.onCancel = sub.cancel;
    });
  }

  Future<void> addAccount(String uid, String name) {
    return _accountsRef(uid).add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renameAccount(String uid, String accountId, String name) {
    return _accountsRef(uid).doc(accountId).update({'name': name});
  }

  /// Ensures a "Personal" default account exists, and tags any expenses,
  /// budgets, and recurring templates created before multi-account support
  /// existed so they keep showing up under it.
  Future<void> ensureDefaultAccount(String uid) async {
    final defaultDoc = _accountsRef(uid).doc(defaultAccountId);
    final snap = await defaultDoc.get();
    if (snap.exists) return;

    await defaultDoc.set({
      'name': defaultAccountName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _db.batch();
    var hasWrites = false;

    for (final collection in ['expenses', 'recurring']) {
      final docs = await _db.collection('users').doc(uid).collection(collection).get();
      for (final doc in docs.docs) {
        if (doc.data()['accountId'] == null) {
          batch.update(doc.reference, {'accountId': defaultAccountId});
          hasWrites = true;
        }
      }
    }

    final budgetDocs = await _db.collection('users').doc(uid).collection('budgets').get();
    for (final doc in budgetDocs.docs) {
      if (!doc.id.contains('_')) {
        final newRef = _db.collection('users').doc(uid).collection('budgets').doc('${defaultAccountId}_${doc.id}');
        batch.set(newRef, doc.data());
        batch.delete(doc.reference);
        hasWrites = true;
      }
    }

    if (hasWrites) await batch.commit();
  }
}
