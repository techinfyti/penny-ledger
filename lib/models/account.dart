import 'package:cloud_firestore/cloud_firestore.dart';

const String defaultAccountId = 'personal';
const String defaultAccountName = 'Personal';

class Account {
  final String id;
  final String name;
  final DateTime createdAt;

  Account({required this.id, required this.name, required this.createdAt});

  factory Account.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Account(
      id: doc.id,
      name: data['name'] as String? ?? 'Account',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
