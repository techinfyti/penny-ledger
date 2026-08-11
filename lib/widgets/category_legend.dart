import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/currency_service.dart';
import 'category_colors.dart';

class CategoryLegend extends StatelessWidget {
  final Map<String, double> totals;

  const CategoryLegend({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final currencySymbol = context.watch<CurrencyService>().symbol;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: totals.entries.map((entry) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, color: colorForCategory(entry.key)),
            const SizedBox(width: 6),
            Text('${entry.key}: $currencySymbol${entry.value.toStringAsFixed(0)}'),
          ],
        );
      }).toList(),
    );
  }
}
