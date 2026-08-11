import 'package:flutter/material.dart';

class _Insight {
  final String category;
  final double percentChange;
  final double current;
  final double previous;

  _Insight(this.category, this.percentChange, this.current, this.previous);
}

class SpendingInsights extends StatelessWidget {
  final Map<String, double> currentByCategory;
  final Map<String, double> previousByCategory;
  final double currentTotal;
  final double previousTotal;
  final String currencySymbol;

  const SpendingInsights({
    super.key,
    required this.currentByCategory,
    required this.previousByCategory,
    required this.currentTotal,
    required this.previousTotal,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    if (previousTotal <= 0) {
      return const SizedBox.shrink();
    }

    final insights = <_Insight>[];
    for (final category in currentByCategory.keys) {
      final curr = currentByCategory[category] ?? 0;
      final prev = previousByCategory[category] ?? 0;
      if (prev <= 0) continue;
      final change = ((curr - prev) / prev) * 100;
      if (change.abs() >= 15) {
        insights.add(_Insight(category, change, curr, prev));
      }
    }
    insights.sort((a, b) => b.percentChange.abs().compareTo(a.percentChange.abs()));
    final topInsights = insights.take(3).toList();

    final overallChange = ((currentTotal - previousTotal) / previousTotal) * 100;

    if (topInsights.isEmpty && overallChange.abs() < 5) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          if (overallChange.abs() >= 5)
            _InsightRow(
              text:
                  'Total spending is ${overallChange.abs().toStringAsFixed(0)}% '
                  '${overallChange > 0 ? 'higher' : 'lower'} than last month',
              isIncrease: overallChange > 0,
            ),
          for (final insight in topInsights)
            _InsightRow(
              text:
                  '${insight.category} spending is ${insight.percentChange.abs().toStringAsFixed(0)}% '
                  '${insight.percentChange > 0 ? 'higher' : 'lower'} than last month',
              isIncrease: insight.percentChange > 0,
            ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final String text;
  final bool isIncrease;

  const _InsightRow({required this.text, required this.isIncrease});

  @override
  Widget build(BuildContext context) {
    final color = isIncrease ? Colors.red.shade400 : Colors.green.shade400;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isIncrease ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
