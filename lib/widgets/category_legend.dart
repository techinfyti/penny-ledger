import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/currency_service.dart';
import 'category_colors.dart';

class CategoryLegend extends StatelessWidget {
  final Map<String, double> totals;
  final bool showPercent;

  const CategoryLegend({super.key, required this.totals, this.showPercent = false});

  @override
  Widget build(BuildContext context) {
    final currencySymbol = context.watch<CurrencyService>().symbol;
    final sum = totals.values.fold<double>(0, (total, v) => total + v);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: totals.entries.map((entry) {
        final percent = showPercent && sum > 0 ? ' (${(entry.value / sum * 100).toStringAsFixed(0)}%)' : '';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, color: colorForCategory(entry.key)),
            const SizedBox(width: 6),
            Text('${entry.key}: $currencySymbol${entry.value.toStringAsFixed(0)}$percent'),
          ],
        );
      }).toList(),
    );
  }
}
