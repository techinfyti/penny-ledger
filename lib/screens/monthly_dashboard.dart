import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/account_service.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../services/group_service.dart';
import '../services/pdf_report_service.dart';
import '../widgets/category_colors.dart';
import '../widgets/category_legend.dart';
import '../widgets/chart_axis.dart';
import '../widgets/currency_selector_button.dart';
import '../widgets/group_filter_chips.dart';
import '../widgets/legend_dot.dart';
import '../widgets/logout_button.dart';
import '../widgets/spending_insights.dart';
import '../widgets/summary_card.dart';

class MonthlyDashboard extends StatefulWidget {
  final String uid;

  const MonthlyDashboard({super.key, required this.uid});

  @override
  State<MonthlyDashboard> createState() => _MonthlyDashboardState();
}

class _MonthlyDashboardState extends State<MonthlyDashboard> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<Expense> _currentTransactions = [];
  bool _exporting = false;
  String? _groupFilter;

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  Future<Map<String, String>> _groupNames() async {
    final groups = await context.read<GroupService>().groupsFor(widget.uid).first;
    return {for (final g in groups) g.id: g.name};
  }

  Future<void> _exportPdf() async {
    final pdfService = context.read<PdfReportService>();
    final currencyCode = context.read<CurrencyService>().currency.code;
    setState(() => _exporting = true);
    try {
      await pdfService.shareReport(
        title: 'Monthly Expense Report',
        subtitle: DateFormat('MMMM yyyy').format(_selectedMonth),
        transactions: _currentTransactions,
        currencyCode: currencyCode,
        groupNames: await _groupNames(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printReport() async {
    final pdfService = context.read<PdfReportService>();
    final currencyCode = context.read<CurrencyService>().currency.code;
    setState(() => _exporting = true);
    try {
      await pdfService.printReport(
        title: 'Monthly Expense Report',
        subtitle: DateFormat('MMMM yyyy').format(_selectedMonth),
        transactions: _currentTransactions,
        currencyCode: currencyCode,
        groupNames: await _groupNames(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    final accountId = context.watch<AccountService>().currentAccountId;
    final currencySymbol = context.watch<CurrencyService>().symbol;
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final daysInMonth = DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly'),
        actions: [
          const CurrencySelectorButton(),
          PopupMenuButton<String>(
            enabled: !_exporting,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'PDF report',
            onSelected: (value) => value == 'print' ? _printReport() : _exportPdf(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'share', child: Text('Download / Share PDF')),
              PopupMenuItem(value: 'print', child: Text('Print')),
            ],
          ),
          const LogoutButton(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
                Expanded(
                  child: Center(
                    child: Text(monthLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrentMonth ? null : () => _changeMonth(1),
                ),
              ],
            ),
          ),
          GroupFilterChips(
            uid: widget.uid,
            selectedGroupId: _groupFilter,
            onChanged: (value) => setState(() => _groupFilter = value),
          ),
          Expanded(
            child: StreamBuilder<List<Expense>>(
              stream: firestore.expensesForMonth(widget.uid, accountId, _selectedMonth),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var transactions = snapshot.data ?? [];
                if (_groupFilter != null) {
                  transactions = transactions.where((e) => e.groupId == _groupFilter).toList();
                }
                _currentTransactions = transactions;
                final expenses = transactions.where((e) => e.type == TransactionType.expense).toList();
                final incomes = transactions.where((e) => e.type == TransactionType.income).toList();
                final incomeTotal = incomes.fold<double>(0, (sum, e) => sum + e.amount);
                final expenseTotal = expenses.fold<double>(0, (sum, e) => sum + e.amount);

                final expenseByDay = <int, double>{};
                for (final e in expenses) {
                  expenseByDay[e.date.day] = (expenseByDay[e.date.day] ?? 0) + e.amount;
                }
                final incomeByDay = <int, double>{};
                for (final e in incomes) {
                  incomeByDay[e.date.day] = (incomeByDay[e.date.day] ?? 0) + e.amount;
                }
                final byCategory = totalsByCategory(expenses);
                final incomeByCategory = totalsByCategory(incomes);
                final allDayValues = [...expenseByDay.values, ...incomeByDay.values];
                final maxDayTotal = allDayValues.isEmpty ? 1.0 : allDayValues.reduce((a, b) => a > b ? a : b);
                final dayChartAxis = niceYAxis(maxDayTotal * 1.2);
                final previousMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);

                return StreamBuilder<List<Expense>>(
                  stream: firestore.expensesForMonth(widget.uid, accountId, previousMonth),
                  builder: (context, prevSnapshot) {
                    var prevExpenses = (prevSnapshot.data ?? [])
                        .where((e) => e.type == TransactionType.expense)
                        .toList();
                    if (_groupFilter != null) {
                      prevExpenses = prevExpenses.where((e) => e.groupId == _groupFilter).toList();
                    }
                    final prevByCategory = totalsByCategory(prevExpenses);
                    final prevTotal = prevExpenses.fold<double>(0, (sum, e) => sum + e.amount);

                    return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SummaryCard(income: incomeTotal, expense: expenseTotal, currencySymbol: currencySymbol),
                    const SizedBox(height: 24),
                    SpendingInsights(
                      currentByCategory: byCategory,
                      previousByCategory: prevByCategory,
                      currentTotal: expenseTotal,
                      previousTotal: prevTotal,
                      currencySymbol: currencySymbol,
                    ),
                    if (expenses.isEmpty && incomes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('No transactions this month')),
                      )
                    else ...[
                      const Text('Income vs Expense by day', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 220,
                        child: BarChart(
                          BarChartData(
                            maxY: dayChartAxis.maxY,
                            barGroups: List.generate(daysInMonth, (i) {
                              final day = i + 1;
                              return BarChartGroupData(x: day, barRods: [
                                BarChartRodData(
                                  toY: incomeByDay[day] ?? 0,
                                  color: Colors.green.shade400,
                                  width: 5,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                BarChartRodData(
                                  toY: expenseByDay[day] ?? 0,
                                  color: Colors.red.shade400,
                                  width: 5,
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
                                  interval: dayChartAxis.interval,
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 24,
                                  getTitlesWidget: (value, meta) {
                                    final day = value.toInt();
                                    final step = daysInMonth > 15 ? 5 : 2;
                                    if (day % step != 0) return const SizedBox.shrink();
                                    return Text(
                                      day.toString(),
                                      style: const TextStyle(fontSize: 10),
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
                          LegendDot(color: Colors.green, label: 'Income'),
                          SizedBox(width: 16),
                          LegendDot(color: Colors.red, label: 'Expense'),
                        ],
                      ),
                      if (expenses.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const Text('Expenses by category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 220,
                          child: PieChart(
                            PieChartData(
                              sections: byCategory.entries.map((entry) {
                                final pct = expenseTotal == 0 ? 0 : (entry.value / expenseTotal * 100);
                                return PieChartSectionData(
                                  value: entry.value,
                                  color: colorForCategory(entry.key),
                                  title: '${pct.toStringAsFixed(0)}%',
                                  radius: 70,
                                  titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                );
                              }).toList(),
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        CategoryLegend(totals: byCategory),
                      ],
                      if (incomes.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const Text('Income by category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        CategoryLegend(totals: incomeByCategory),
                      ],
                    ],
                  ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
