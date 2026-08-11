import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType {
  expense,
  income;

  String get field => this == TransactionType.income ? 'income' : 'expense';

  static TransactionType fromField(String? value) {
    return value == 'income' ? TransactionType.income : TransactionType.expense;
  }
}

const List<String> defaultExpenseCategories = [
  'Food',
  'Groceries',
  'Transport',
  'Fuel',
  'Bills',
  'Rent',
  'Shopping',
  'Entertainment',
  'Sports',
  'Fitness',
  'Health',
  'Education',
  'Travel',
  'Insurance',
  'Subscriptions',
  'Personal Care',
  'Household',
  'Electronics',
  'Gifts & Donations',
  'Pets',
  'Kids',
  'Loan/EMI',
  'Maintenance',
  'Taxes',
  'Other',
];

const List<String> defaultIncomeCategories = [
  'Salary',
  'Business',
  'Freelance',
  'Investment',
  'Rental Income',
  'Bonus',
  'Interest',
  'Dividend',
  'Cashback',
  'Pension',
  'Gift',
  'Refund',
  'Other Income',
];

List<String> defaultCategoriesFor(TransactionType type) {
  return type == TransactionType.income ? defaultIncomeCategories : defaultExpenseCategories;
}

const List<String> paymentMethods = ['Cash', 'Online', 'Card', 'GPay'];

class Expense {
  final String id;
  final double amount;
  final String category;
  final DateTime date;
  final String note;
  final TransactionType type;
  final String paymentMethod;
  final String accountId;
  final String personName;
  final String? groupId;

  Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    required this.note,
    this.type = TransactionType.expense,
    this.paymentMethod = 'Cash',
    this.accountId = 'personal',
    this.personName = '',
    this.groupId,
  });

  factory Expense.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Expense(
      id: doc.id,
      amount: (data['amount'] as num).toDouble(),
      category: data['category'] as String,
      date: (data['date'] as Timestamp).toDate(),
      note: data['note'] as String? ?? '',
      type: TransactionType.fromField(data['type'] as String?),
      paymentMethod: data['paymentMethod'] as String? ?? 'Cash',
      accountId: data['accountId'] as String? ?? 'personal',
      personName: data['personName'] as String? ?? '',
      groupId: data['groupId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'category': category,
      'date': Timestamp.fromDate(date),
      'note': note,
      'type': type.field,
      'paymentMethod': paymentMethod,
      'accountId': accountId,
      'personName': personName,
      'groupId': groupId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
