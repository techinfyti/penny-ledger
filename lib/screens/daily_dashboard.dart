import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/account_service.dart';
import '../services/firestore_service.dart';
import '../services/group_service.dart';
import '../services/pdf_report_service.dart';
import '../services/currency_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/currency_selector_button.dart';
import '../widgets/group_filter_chips.dart';
import '../widgets/logout_button.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_tile.dart';
import 'settings_screen.dart';

class DailyDashboard extends StatefulWidget {
  final String uid;

  const DailyDashboard({super.key, required this.uid});

  @override
  State<DailyDashboard> createState() => _DailyDashboardState();
}

class _DailyDashboardState extends State<DailyDashboard> {
  DateTime _selectedDay = DateTime.now();
  List<Expense> _currentTransactions = [];
  bool _exporting = false;
  String? _groupFilter;

  void _changeDay(int deltaDays) {
    setState(() => _selectedDay = _selectedDay.add(Duration(days: deltaDays)));
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDay = picked);
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
        title: 'PennyLedger Report',
        subtitle: DateFormat('EEEE, MMM d, yyyy').format(_selectedDay),
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
        title: 'PennyLedger Report',
        subtitle: DateFormat('EEEE, MMM d, yyyy').format(_selectedDay),
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
    final dateLabel = DateFormat('EEEE, MMM d, yyyy').format(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsScreen(uid: widget.uid)),
              );
            },
          ),
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
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeDay(-1),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDay,
                    child: Center(
                      child: Text(
                        dateLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: DateUtils.isSameDay(_selectedDay, DateTime.now())
                      ? null
                      : () => _changeDay(1),
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
              stream: firestore.expensesForDay(widget.uid, accountId, _selectedDay),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var transactions = snapshot.data ?? [];
                if (_groupFilter != null) {
                  transactions = transactions.where((e) => e.groupId == _groupFilter).toList();
                }
                _currentTransactions = transactions;
                final income = transactions
                    .where((e) => e.type == TransactionType.income)
                    .fold<double>(0, (sum, e) => sum + e.amount);
                final expense = transactions
                    .where((e) => e.type == TransactionType.expense)
                    .fold<double>(0, (sum, e) => sum + e.amount);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SummaryCard(income: income, expense: expense, currencySymbol: currencySymbol),
                    ),
                    Expanded(
                      child: transactions.isEmpty
                          ? const Center(child: Text('No transactions on this day'))
                          : ListView.builder(
                              itemCount: transactions.length,
                              itemBuilder: (context, index) {
                                return TransactionTile(
                                  uid: widget.uid,
                                  expense: transactions[index],
                                  currencySymbol: currencySymbol,
                                );
                              },
                            ),
                    ),
                    const BannerAdWidget(),
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
