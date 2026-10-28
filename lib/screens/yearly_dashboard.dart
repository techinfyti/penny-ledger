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
import '../widgets/settings_button.dart';
import '../widgets/summary_card.dart';
import '../services/csv_export_service.dart';
import '../services/premium_service.dart';
import 'premium_screen.dart';
import 'recurring_screen.dart';
import 'statement_import_screen.dart';

class YearlyDashboard extends StatefulWidget {
  final String uid;

  const YearlyDashboard({super.key, required this.uid});

  @override
  State<YearlyDashboard> createState() => _YearlyDashboardState();
}

class _YearlyDashboardState extends State<YearlyDashboard> {
  int _selectedYear = DateTime.now().year;
  List<Expense> _currentTransactions = [];
  bool _exporting = false;
  String? _groupFilter;

  void _changeYear(int delta) {
    setState(() => _selectedYear += delta);
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
        title: 'Yearly Expense Report',
        subtitle: '$_selectedYear',
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
        title: 'Yearly Expense Report',
        subtitle: '$_selectedYear',
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

  Future<void> _exportCsv() async {
    final isPremium = context.read<PremiumService>().isPremium;
    if (!isPremium) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PremiumScreen(uid: widget.uid)),
      );
      return;
    }
    final csvService = context.read<CsvExportService>();
    setState(() => _exporting = true);
    try {
      await csvService.shareCsv(
        filenamePrefix: 'yearly',
        transactions: _currentTransactions,
        groupNames: await _groupNames(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
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
    final isCurrentYear = _selectedYear == DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yearly'),
        actions: [
          SettingsButton(uid: widget.uid),
          const CurrencySelectorButton(),
          PopupMenuButton<String>(
            enabled: !_exporting,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'import':
                  openStatementImport(context, widget.uid);
                  break;
                case 'share':
                  _exportPdf();
                  break;
                case 'print':
                  _printReport();
                  break;
                case 'csv':
                  _exportCsv();
                  break;
                case 'recurring':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RecurringScreen(uid: widget.uid)),
                  );
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'import', child: Text('Import Transactions')),
              PopupMenuItem(value: 'share', child: Text('Download / Share PDF')),
              PopupMenuItem(value: 'print', child: Text('Print PDF')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'recurring', child: Text('Recurring transactions')),
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
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeYear(-1)),
                Expanded(
                  child: Center(
                    child: Text('$_selectedYear', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrentYear ? null : () => _changeYear(1),
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
              stream: firestore.expensesForYear(widget.uid, accountId, _selectedYear),
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

                final expenseByMonth = <int, double>{};
                for (final e in expenses) {
                  expenseByMonth[e.date.month] = (expenseByMonth[e.date.month] ?? 0) + e.amount;
                }
                final incomeByMonth = <int, double>{};
                for (final e in incomes) {
                  incomeByMonth[e.date.month] = (incomeByMonth[e.date.month] ?? 0) + e.amount;
                }
                final byCategory = totalsByCategory(expenses);
                final incomeByCategory = totalsByCategory(incomes);
                final allMonthValues = [...expenseByMonth.values, ...incomeByMonth.values];
                final maxMonthTotal = allMonthValues.isEmpty ? 1.0 : allMonthValues.reduce((a, b) => a > b ? a : b);
                final monthChartAxis = niceYAxis(maxMonthTotal * 1.2);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SummaryCard(income: incomeTotal, expense: expenseTotal, currencySymbol: currencySymbol),
                    const SizedBox(height: 24),
                    if (expenses.isEmpty && incomes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('No transactions this year')),
                      )
                    else ...[
                      const Text('Income vs Expense by month', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 220,
                        child: BarChart(
                          BarChartData(
                            maxY: monthChartAxis.maxY,
                            barGroups: List.generate(12, (i) {
                              final month = i + 1;
                              return BarChartGroupData(x: month, barRods: [
                                BarChartRodData(
                                  toY: incomeByMonth[month] ?? 0,
                                  color: Colors.green.shade400,
                                  width: 10,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                BarChartRodData(
                                  toY: expenseByMonth[month] ?? 0,
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
                                  interval: monthChartAxis.interval,
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) => Text(
                                    DateFormat('MMM').format(DateTime(_selectedYear, value.toInt())),
                                    style: const TextStyle(fontSize: 10),
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}
