import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/firestore_service.dart';
import '../screens/add_expense_screen.dart';

class TransactionTile extends StatelessWidget {
  final String uid;
  final Expense expense;
  final String currencySymbol;
  final String Function(Expense)? subtitleBuilder;

  const TransactionTile({
    super.key,
    required this.uid,
    required this.expense,
    required this.currencySymbol,
    this.subtitleBuilder,
  });

  Future<void> _delete(BuildContext context) async {
    final firestore = context.read<FirestoreService>();
    await firestore.deleteExpense(uid, expense.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction deleted')),
      );
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete transaction?'),
            content: Text('${expense.category} · $currencySymbol${expense.amount.toStringAsFixed(2)}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = expense.type == TransactionType.income;
    final color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
    final defaultParts = [
      if (expense.personName.isNotEmpty) expense.personName,
      if (expense.note.isNotEmpty) expense.note,
    ];
    final subtitle = subtitleBuilder?.call(expense) ?? (defaultParts.isNotEmpty ? defaultParts.join(' · ') : null);

    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => _delete(context),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Text(expense.category),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isIncome ? '+' : '-'}$currencySymbol${expense.amount.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: 'Delete',
              onPressed: () async {
                final confirmed = await _confirmDelete(context);
                if (confirmed && context.mounted) await _delete(context);
              },
            ),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddExpenseScreen(uid: uid, existing: expense),
            ),
          );
        },
      ),
    );
  }
}
