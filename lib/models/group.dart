import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseGroup {
  final String id;
  final String name;
  final DateTime createdAt;

  ExpenseGroup({required this.id, required this.name, required this.createdAt});

  factory ExpenseGroup.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ExpenseGroup(
      id: doc.id,
      name: data['name'] as String? ?? 'Group',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
