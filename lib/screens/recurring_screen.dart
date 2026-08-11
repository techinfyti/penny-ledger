import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../models/recurring_transaction.dart';
import '../services/account_service.dart';
import '../services/currency_service.dart';
import '../services/recurring_service.dart';
import '../widgets/category_colors.dart';

class RecurringScreen extends StatelessWidget {
  final String uid;

  const RecurringScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final recurringService = context.read<RecurringService>();
    final accountId = context.watch<AccountService>().currentAccountId;
    final currencySymbol = context.watch<CurrencyService>().symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Transactions')),
      body: StreamBuilder<List<RecurringTransaction>>(
        stream: recurringService.allRecurring(uid, accountId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final templates = snapshot.data ?? [];
          if (templates.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No recurring transactions yet.\nEnable "Repeat monthly" when adding a transaction to create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              final isIncome = t.type == TransactionType.income;
              final color = isIncome ? Colors.green.shade400 : Colors.red.shade400;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorForCategory(t.category).withOpacity(0.15),
                    child: Icon(
                      isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                      color: color,
                    ),
                  ),
                  title: Text(t.category),
                  subtitle: Text('Day ${t.dayOfMonth} of every month · ${t.paymentMethod}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isIncome ? '+' : '-'}$currencySymbol${t.amount.toStringAsFixed(0)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: color),
                      ),
                      Switch(
                        value: t.active,
                        onChanged: (value) => recurringService.setActive(uid, t.id, value),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete recurring transaction?'),
                              content: Text('${t.category} · $currencySymbol${t.amount.toStringAsFixed(0)}/month'),
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
                          );
                          if (confirmed == true) {
                            await recurringService.deleteRecurring(uid, t.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
