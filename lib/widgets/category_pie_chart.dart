import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'category_colors.dart';

/// Expense share per category. Slices below [minLabelPercent] get no label,
/// because with many categories the labels overlap; the legend below the
/// chart lists every category with its percentage.
class CategoryPieChart extends StatelessWidget {
  final Map<String, double> totals;
  final double minLabelPercent;

  const CategoryPieChart({super.key, required this.totals, this.minLabelPercent = 6});

  @override
  Widget build(BuildContext context) {
    final total = totals.values.fold<double>(0, (sum, v) => sum + v);
    return SizedBox(
      height: 220,
      child: PieChart(
        PieChartData(
          sections: totals.entries.map((entry) {
            final pct = total == 0 ? 0.0 : entry.value / total * 100;
            return PieChartSectionData(
              value: entry.value,
              color: colorForCategory(entry.key),
              title: pct >= minLabelPercent ? '${pct.toStringAsFixed(0)}%' : '',
              radius: 70,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            );
          }).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 40,
        ),
      ),
    );
  }
}
