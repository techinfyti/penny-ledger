import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/account_service.dart';
import '../services/budget_service.dart';
import '../services/category_service.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../widgets/category_colors.dart';
import '../widgets/chart_axis.dart';
import '../widgets/currency_selector_button.dart';
import '../widgets/group_filter_chips.dart';
import '../widgets/legend_dot.dart';
import '../widgets/logout_button.dart';
import '../widgets/stat_card.dart';

class BudgetScreen extends StatefulWidget {
  final String uid;

  const BudgetScreen({super.key, required this.uid});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  String? _groupFilter;

  Future<void> _editCategoryLimit(BuildContext context, String accountId, String category, double? currentLimit) async {
    final budgetService = context.read<BudgetService>();
    final controller = TextEditingController(
      text: currentLimit != null && currentLimit > 0 ? currentLimit.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set limit for $category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Limit amount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              Navigator.of(context).pop(value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    await budgetService.setCategoryLimit(widget.uid, accountId, DateTime.now(), category, result);
  }

  @override
  Widget build(BuildContext context) {
    final budgetService = context.read<BudgetService>();
    final categoryService = context.read<CategoryService>();
    final firestore = context.read<FirestoreService>();
    final accountId = context.watch<AccountService>().currentAccountId;
    final currencySymbol = context.watch<CurrencyService>().symbol;
    final now = DateTime.now();
    final monthLabel = DateFormat('MMMM yyyy').format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: const [CurrencySelectorButton(), LogoutButton()],
      ),
      body: StreamBuilder<List<Expense>>(
        stream: firestore.expensesForMonth(widget.uid, accountId, now),
        builder: (context, txSnapshot) {
          final transactions = txSnapshot.data ?? [];
          var expenses = transactions.where((e) => e.type == TransactionType.expense).toList();
          if (_groupFilter != null) {
            expenses = expenses.where((e) => e.groupId == _groupFilter).toList();
          }
          final spentByCategory = totalsByCategory(expenses);

          return StreamBuilder<Map<String, double>>(
            stream: budgetService.categoryLimitsForMonth(widget.uid, accountId, now),
            builder: (context, categoryBudgetSnapshot) {
              final categoryLimits = categoryBudgetSnapshot.data ?? {};

              return StreamBuilder<List<String>>(
                stream: categoryService.categoriesFor(widget.uid, TransactionType.expense),
                builder: (context, categoriesSnapshot) {
                  final categories = categoriesSnapshot.data ?? defaultCategoriesFor(TransactionType.expense);

                  final budgetedCategories =
                      categories.where((c) => (categoryLimits[c] ?? 0) > 0).toList();
                  final totalBudgeted =
                      budgetedCategories.fold<double>(0, (sum, c) => sum + (categoryLimits[c] ?? 0));
                  final totalSpent =
                      budgetedCategories.fold<double>(0, (sum, c) => sum + (spentByCategory[c] ?? 0));
                  final remaining = totalBudgeted - totalSpent;
                  final maxBarValue = [
                    ...budgetedCategories.map((c) => categoryLimits[c] ?? 0),
                    ...budgetedCategories.map((c) => spentByCategory[c] ?? 0),
                  ].fold<double>(1, (max, v) => v > max ? v : max);
                  final budgetChartAxis = niceYAxis(maxBarValue * 1.2);

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Budget Overview', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        monthLabel,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      GroupFilterChips(
                        uid: widget.uid,
                        selectedGroupId: _groupFilter,
                        onChanged: (value) => setState(() => _groupFilter = value),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              label: 'Budgeted',
                              value: totalBudgeted,
                              currencySymbol: currencySymbol,
                              accentColor: Colors.blue.shade400,
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StatCard(
                              label: 'Spent',
                              value: totalSpent,
                              currencySymbol: currencySymbol,
                              accentColor: Colors.red.shade400,
                              icon: Icons.trending_down,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StatCard(
                        label: 'Remaining',
                        value: remaining,
                        currencySymbol: currencySymbol,
                        accentColor: remaining >= 0 ? Colors.green.shade400 : Colors.deepOrange.shade400,
                        icon: Icons.savings_outlined,
                      ),
                      if (budgetedCategories.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        const Text('Budget vs Spent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 220,
                          child: BarChart(
                            BarChartData(
                              maxY: budgetChartAxis.maxY,
                              barGroups: List.generate(budgetedCategories.length, (i) {
                                final category = budgetedCategories[i];
                                return BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: categoryLimits[category] ?? 0,
                                    color: Colors.blue.shade400,
                                    width: 10,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  BarChartRodData(
                                    toY: spentByCategory[category] ?? 0,
                                    color: Colors.red.shade400,
                                    width: 10,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ]);
                              }),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 44,
                                    interval: budgetChartAxis.interval,
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index < 0 || index >= budgetedCategories.length) {
                                        return const SizedBox.shrink();
                                      }
                                      final name = budgetedCategories[index];
                                      final short = name.length > 3 ? name.substring(0, 3) : name;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(short, style: const TextStyle(fontSize: 10)),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              gridData: const FlGridData(show: true, drawVerticalLine: false),
                              borderData: FlBorderData(show: false),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LegendDot(color: Colors.blue, label: 'Budget'),
                            SizedBox(width: 16),
                            LegendDot(color: Colors.red, label: 'Spent'),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Set a limit on any category below to see it charted here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      Text('Category Budgets', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Monthly limits · $monthLabel · ${context.watch<CurrencyService>().currency.code}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      ...categories.map((category) {
                        final categoryLimit = categoryLimits[category];
                        final categorySpent = spentByCategory[category] ?? 0;
                        return _CategoryBudgetTile(
                          category: category,
                          limit: categoryLimit,
                          spent: categorySpent,
                          currencySymbol: currencySymbol,
                          onEdit: () => _editCategoryLimit(context, accountId, category, categoryLimit),
                        );
                      }),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryBudgetTile extends StatelessWidget {
  final String category;
  final double? limit;
  final double spent;
  final String currencySymbol;
  final VoidCallback onEdit;

  const _CategoryBudgetTile({
    required this.category,
    required this.limit,
    required this.spent,
    required this.currencySymbol,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasLimit = limit != null && limit! > 0;
    final progress = hasLimit ? (spent / limit!).clamp(0.0, 1.0) : 0.0;
    final isOverBudget = hasLimit && spent > limit!;
    final progressColor = isOverBudget
        ? Colors.red.shade400
        : (progress > 0.8 ? Colors.orange.shade400 : Colors.green.shade400);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colorForCategory(category).withOpacity(0.15),
                child: Text(
                  category.isNotEmpty ? category[0].toUpperCase() : '?',
                  style: TextStyle(color: colorForCategory(category), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(category, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: Icon(hasLimit ? Icons.edit_outlined : Icons.add, size: 16),
                label: Text(hasLimit ? 'Edit' : 'Set Limit'),
              ),
            ],
          ),
          if (!hasLimit)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 4),
              child: Text(
                'No limit set',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Theme.of(context).colorScheme.surface,
                valueColor: AlwaysStoppedAnimation(progressColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$currencySymbol${spent.toStringAsFixed(0)} of $currencySymbol${limit!.toStringAsFixed(0)} spent'
              '${isOverBudget ? ' (over budget)' : ''}',
              style: TextStyle(fontSize: 12, color: progressColor, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
