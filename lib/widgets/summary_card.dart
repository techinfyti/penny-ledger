import 'package:flutter/material.dart';
import 'stat_card.dart';

class SummaryCard extends StatelessWidget {
  final double income;
  final double expense;
  final String currencySymbol;

  const SummaryCard({
    super.key,
    required this.income,
    required this.expense,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final net = income - expense;
    final netColor = net >= 0 ? Colors.green.shade400 : Colors.deepOrange.shade400;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Income',
                value: income,
                currencySymbol: currencySymbol,
                accentColor: Colors.green.shade400,
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                label: 'Expense',
                value: expense,
                currencySymbol: currencySymbol,
                accentColor: Colors.red.shade400,
                icon: Icons.trending_down,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatCard(
          label: 'Net Balance',
          value: net,
          currencySymbol: currencySymbol,
          accentColor: netColor,
          icon: Icons.account_balance_wallet_outlined,
        ),
      ],
    );
  }
}
