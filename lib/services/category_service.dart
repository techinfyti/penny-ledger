import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';

class CategoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _categoriesDoc(String uid) {
    return _db.collection('users').doc(uid).collection('meta').doc('categories');
  }

  CollectionReference<Map<String, dynamic>> _expensesRef(String uid) {
    return _db.collection('users').doc(uid).collection('expenses');
  }

  // One underlying Firestore listener per uid+type, shared across every
  // caller. categoriesFor() wraps it in Stream.multi() so a listener that
  // subscribes after the first snapshot already arrived is replayed the
  // latest value immediately instead of sitting empty until the next
  // Firestore write.
  final Map<String, Stream<List<String>>> _broadcast = {};
  final Map<String, List<String>> _latest = {};

  Stream<List<String>> categoriesFor(String uid, TransactionType type) {
    final key = '$uid:${type.field}';
    _broadcast.putIfAbsent(key, () {
      final controller = StreamController<List<String>>.broadcast();
      _categoriesDoc(uid).snapshots().listen((doc) {
        final custom = List<String>.from(doc.data()?[type.field] as List? ?? []);
        final defaults = defaultCategoriesFor(type);
        final merged = [...defaults];
        for (final c in custom) {
          if (!merged.contains(c)) merged.add(c);
        }
        _latest[key] = merged;
        controller.add(merged);
      });
      return controller.stream;
    });

    return Stream<List<String>>.multi((controller) {
      final cached = _latest[key];
      if (cached != null) controller.add(cached);
      final sub = _broadcast[key]!.listen(controller.add, onError: controller.addError, onDone: controller.close);
      controller.onCancel = sub.cancel;
    });
  }

  /// Only the categories the user added themselves (not the built-in defaults).
  Stream<List<String>> customCategoriesFor(String uid, TransactionType type) {
    return _categoriesDoc(uid).snapshots().map((doc) {
      return List<String>.from(doc.data()?[type.field] as List? ?? []);
    });
  }

  Future<void> addCategory(String uid, TransactionType type, String name) async {
    await _categoriesDoc(uid).set({
      type.field: FieldValue.arrayUnion([name]),
    }, SetOptions(merge: true));
  }

  /// Renames a custom category everywhere: the saved category list and every
  /// past transaction that used the old name.
  Future<void> renameCategory(
    String uid,
    TransactionType type,
    String oldName,
    String newName,
  ) async {
    await _categoriesDoc(uid).update({
      type.field: FieldValue.arrayRemove([oldName]),
    });
    await _categoriesDoc(uid).set({
      type.field: FieldValue.arrayUnion([newName]),
    }, SetOptions(merge: true));

    final matching = await _expensesRef(uid).where('category', isEqualTo: oldName).get();
    if (matching.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in matching.docs) {
      batch.update(doc.reference, {'category': newName});
    }
    await batch.commit();
  }

  /// Removes any custom category the user added that now duplicates a
  /// built-in default (e.g. a default added later that matches one they'd
  /// already created themselves). Existing transactions keep their category
  /// name unchanged since the default now covers it.
  Future<void> pruneCustomCategoriesMatchingDefaults(String uid) async {
    final doc = await _categoriesDoc(uid).get();
    final data = doc.data();
    if (data == null) return;

    final updates = <String, dynamic>{};
    for (final type in TransactionType.values) {
      final custom = List<String>.from(data[type.field] as List? ?? []);
      final defaults = defaultCategoriesFor(type);
      final duplicates = custom.where((c) => defaults.contains(c)).toList();
      if (duplicates.isNotEmpty) {
        updates[type.field] = FieldValue.arrayRemove(duplicates);
      }
    }
    if (updates.isNotEmpty) {
      await _categoriesDoc(uid).update(updates);
    }
  }
}
