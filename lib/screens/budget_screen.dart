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
import '../widgets/month_picker.dart';
import '../widgets/settings_button.dart';
import '../widgets/stat_card.dart';

class BudgetScreen extends StatefulWidget {
  final String uid;

  const BudgetScreen({super.key, required this.uid});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  String? _groupFilter;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  Future<void> _chooseMonth() async {
    final picked = await pickMonth(context, _month);
    if (picked != null) setState(() => _month = picked);
  }

  Future<void> _copyFromPreviousMonth(String accountId) async {
    final budgetService = context.read<BudgetService>();
    final messenger = ScaffoldMessenger.of(context);
    final previous = DateTime(_month.year, _month.month - 1);
    final label = DateFormat('MMMM yyyy').format(previous);
    try {
      final copied = await budgetService.copyLimits(widget.uid, accountId, previous, _month);
      messenger.showSnackBar(SnackBar(
        content: Text(copied == 0
            ? 'Nothing to copy from $label (it has no limits, or this month already has them).'
            : 'Copied $copied ${copied == 1 ? 'limit' : 'limits'} from $label.'),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t copy the budget. Check your connection and try again.')));
    }
  }

  Future<void> _editCategoryLimit(BuildContext context, String accountId, String category, double? currentLimit) async {
    final budgetService = context.read<BudgetService>();
    final controller = TextEditingController(
      text: currentLimit != null && currentLimit > 0 ? currentLimit.toStringAsFixed(0) : '',
    );
    var limitMonth = _month;
    final hasCurrentLimit = currentLimit != null && currentLimit > 0;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Set limit for $category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Limit amount'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('Month: ${DateFormat('MMMM yyyy').format(limitMonth)}'),
                onPressed: () async {
                  final picked = await pickMonth(context, limitMonth);
                  if (picked != null) setDialogState(() => limitMonth = picked);
                },
              ),
            ],
          ),
          actions: [
            if (hasCurrentLimit && limitMonth == _month)
              TextButton(
                onPressed: () => Navigator.of(context).pop(-1.0),
                child: Text('Remove limit', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
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
      ),
    );
    if (result == null) return;
    if (result == -1.0) {
      await budgetService.clearCategoryLimit(widget.uid, accountId, _month, category);
      return;
    }
    if (result <= 0) return;
    await budgetService.setCategoryLimit(widget.uid, accountId, limitMonth, category, result);
    if (mounted) setState(() => _month = limitMonth);
  }

  @override
  Widget build(BuildContext context) {
    final budgetService = context.read<BudgetService>();
    final categoryService = context.read<CategoryService>();
    final firestore = context.read<FirestoreService>();
    final accountId = context.watch<AccountService>().currentAccountId;
    final currencySymbol = context.watch<CurrencyService>().symbol;
    final month = _month;
    final monthLabel = DateFormat('MMMM yyyy').format(month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [SettingsButton(uid: widget.uid), const CurrencySelectorButton(), const LogoutButton()],
      ),
      body: StreamBuilder<List<Expense>>(
        stream: firestore.expensesForMonth(widget.uid, accountId, month),
        builder: (context, txSnapshot) {
          final transactions = txSnapshot.data ?? [];
          var expenses = transactions.where((e) => e.type == TransactionType.expense).toList();
          if (_groupFilter != null) {
            expenses = expenses.where((e) => e.groupId == _groupFilter).toList();
          }
          final spentByCategory = totalsByCategory(expenses);

          return StreamBuilder<Map<String, double>>(
            stream: budgetService.categoryLimitsForMonth(widget.uid, accountId, month),
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
                      Row(
                        children: [
                          IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous month', onPressed: () => _changeMonth(-1)),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _chooseMonth,
                              icon: const Icon(Icons.calendar_month_outlined, size: 18),
                              label: Text(monthLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next month', onPressed: () => _changeMonth(1)),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _copyFromPreviousMonth(accountId),
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: Text('Copy ${DateFormat('MMMM').format(DateTime(month.year, month.month - 1))}\'s budget'),
                        ),
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
