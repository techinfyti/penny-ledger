import '../../models/expense.dart';

class ImportedTransaction {
  final DateTime date;
  final String description;
  final double amount;
  final TransactionType type;
  final String? upiRef;
  final String paymentMethod;
  String category;
  bool selected;
  bool duplicate;

  ImportedTransaction({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    this.upiRef,
    this.paymentMethod = 'Online',
    this.category = '',
    this.selected = true,
    this.duplicate = false,
  });

  bool get isIncome => type == TransactionType.income;
}

class ParsedStatement {
  final String sourceLabel;
  final List<ImportedTransaction> items;
  final double? statedExpenseTotal;
  final double? statedIncomeTotal;

  ParsedStatement({
    required this.sourceLabel,
    required this.items,
    this.statedExpenseTotal,
    this.statedIncomeTotal,
  });

  double get expenseTotal => items.where((t) => !t.isIncome).fold(0.0, (sum, t) => sum + t.amount);

  double get incomeTotal => items.where((t) => t.isIncome).fold(0.0, (sum, t) => sum + t.amount);

  /// Null when the statement doesn't print totals to check against.
  bool? get totalsMatch {
    if (statedExpenseTotal == null && statedIncomeTotal == null) return null;
    final expenseOk = statedExpenseTotal == null || (expenseTotal - statedExpenseTotal!).abs() < 0.01;
    final incomeOk = statedIncomeTotal == null || (incomeTotal - statedIncomeTotal!).abs() < 0.01;
    return expenseOk && incomeOk;
  }
}

class StatementFormatException implements Exception {
  final String message;

  StatementFormatException(this.message);

  @override
  String toString() => message;
}

class StatementPasswordRequired implements Exception {
  final bool wrongPassword;

  StatementPasswordRequired({this.wrongPassword = false});

  @override
  String toString() => wrongPassword ? 'That password is wrong.' : 'This PDF is password protected.';
}
