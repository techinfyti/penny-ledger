import 'package:cloud_firestore/cloud_firestore.dart';
import 'expense.dart';

class RecurringTransaction {
  final String id;
  final double amount;
  final String category;
  final TransactionType type;
  final String note;
  final String paymentMethod;
  final int dayOfMonth;
  final bool active;
  final String? lastGeneratedMonth;
  final String accountId;
  final String personName;
  final String? groupId;

  RecurringTransaction({
    required this.id,
    required this.amount,
    required this.category,
    required this.type,
    required this.note,
    required this.paymentMethod,
    required this.dayOfMonth,
    this.active = true,
    this.lastGeneratedMonth,
    this.accountId = 'personal',
    this.personName = '',
    this.groupId,
  });

  factory RecurringTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RecurringTransaction(
      id: doc.id,
      amount: (data['amount'] as num).toDouble(),
      category: data['category'] as String,
      type: TransactionType.fromField(data['type'] as String?),
      note: data['note'] as String? ?? '',
      paymentMethod: data['paymentMethod'] as String? ?? 'Cash',
      dayOfMonth: data['dayOfMonth'] as int,
      active: data['active'] as bool? ?? true,
      lastGeneratedMonth: data['lastGeneratedMonth'] as String?,
      accountId: data['accountId'] as String? ?? 'personal',
      personName: data['personName'] as String? ?? '',
      groupId: data['groupId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'category': category,
      'type': type.field,
      'note': note,
      'paymentMethod': paymentMethod,
      'dayOfMonth': dayOfMonth,
      'active': active,
      'lastGeneratedMonth': lastGeneratedMonth,
      'accountId': accountId,
      'personName': personName,
      'groupId': groupId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
