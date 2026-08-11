import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group.dart';

class GroupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // One underlying Firestore listener per uid, shared across every caller so
  // repeated StreamBuilder rebuilds don't each open their own subscription.
  // groupsFor() wraps it in Stream.multi() so a listener that subscribes
  // after the first snapshot already arrived (e.g. Add Transaction opened
  // after the Daily dashboard) is replayed the latest value immediately
  // instead of sitting empty until the next Firestore write.
  final Map<String, Stream<List<ExpenseGroup>>> _broadcast = {};
  final Map<String, List<ExpenseGroup>> _latest = {};

  CollectionReference<Map<String, dynamic>> _groupsRef(String uid) {
    return _db.collection('users').doc(uid).collection('groups');
  }

  Stream<List<ExpenseGroup>> groupsFor(String uid) {
    _broadcast.putIfAbsent(uid, () {
      final controller = StreamController<List<ExpenseGroup>>.broadcast();
      _groupsRef(uid).orderBy('createdAt').snapshots().listen((snap) {
        final list = snap.docs.map(ExpenseGroup.fromFirestore).toList();
        _latest[uid] = list;
        controller.add(list);
      });
      return controller.stream;
    });

    return Stream<List<ExpenseGroup>>.multi((controller) {
      final cached = _latest[uid];
      if (cached != null) controller.add(cached);
      final sub = _broadcast[uid]!.listen(controller.add, onError: controller.addError, onDone: controller.close);
      controller.onCancel = sub.cancel;
    });
  }

  Future<String> addGroup(String uid, String name) async {
    final ref = await _groupsRef(uid).add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameGroup(String uid, String groupId, String name) {
    return _groupsRef(uid).doc(groupId).update({'name': name});
  }

  Future<void> deleteGroup(String uid, String groupId) {
    return _groupsRef(uid).doc(groupId).delete();
  }
}
