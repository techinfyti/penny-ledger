import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../services/account_service.dart';
import '../services/csv_export_service.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../services/group_service.dart';
import '../services/pdf_report_service.dart';
import '../services/premium_service.dart';
import '../widgets/currency_selector_button.dart';
import '../widgets/group_filter_chips.dart';
import '../widgets/logout_button.dart';
import '../widgets/transaction_tile.dart';
import 'premium_screen.dart';
import 'recurring_screen.dart';

enum _TypeFilter { all, income, expense }

enum _SortOrder { dateDesc, dateAsc, amountDesc, amountAsc }

extension on _SortOrder {
  String get label {
    switch (this) {
      case _SortOrder.dateDesc:
        return 'Date: Newest first';
      case _SortOrder.dateAsc:
        return 'Date: Oldest first';
      case _SortOrder.amountDesc:
        return 'Amount: High to low';
      case _SortOrder.amountAsc:
        return 'Amount: Low to high';
    }
  }
}

class HistoryScreen extends StatefulWidget {
  final String uid;

  const HistoryScreen({super.key, required this.uid});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _TypeFilter _filter = _TypeFilter.all;
  _SortOrder _sort = _SortOrder.dateDesc;
  String _query = '';
  DateTimeRange? _dateRange;
  String? _groupFilter;
  List<Expense> _currentTransactions = [];
  bool _exportingCsv = false;
  bool _exportingPdf = false;

  String get _reportSubtitle {
    final range = _dateRange;
    if (range != null) {
      final fmt = DateFormat('MMM d, yyyy');
      return '${fmt.format(range.start)} – ${fmt.format(range.end)}';
    }
    return 'All Transactions';
  }

  Future<Map<String, String>> _groupNames() async {
    final groups = await context.read<GroupService>().groupsFor(widget.uid).first;
    return {for (final g in groups) g.id: g.name};
  }

  Future<void> _exportPdf() async {
    final pdfService = context.read<PdfReportService>();
    final currencyCode = context.read<CurrencyService>().currency.code;
    setState(() => _exportingPdf = true);
    try {
      await pdfService.shareReport(
        title: 'History Report',
        subtitle: _reportSubtitle,
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
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _printReport() async {
    final pdfService = context.read<PdfReportService>();
    final currencyCode = context.read<CurrencyService>().currency.code;
    setState(() => _exportingPdf = true);
    try {
      await pdfService.printReport(
        title: 'History Report',
        subtitle: _reportSubtitle,
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
      if (mounted) setState(() => _exportingPdf = false);
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
    setState(() => _exportingCsv = true);
    try {
      await csvService.shareCsv(
        filenamePrefix: 'history',
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
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    final accountId = context.watch<AccountService>().currentAccountId;
    final currencySymbol = context.watch<CurrencyService>().symbol;
    final dateFormat = DateFormat('MMM d, yyyy');
    final range = _dateRange;

    final busy = _exportingCsv || _exportingPdf;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          PopupMenuButton<String>(
            enabled: !busy,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'share':
                  _exportPdf();
                  break;
                case 'print':
                  _printReport();
                  break;
                case 'csv':
                  _exportCsv();
                  break;
                case 'date':
                  _pickDateRange();
                  break;
                case 'recurring':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => RecurringScreen(uid: widget.uid)),
                  );
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'share', child: Text('Download / Share PDF')),
              PopupMenuItem(value: 'print', child: Text('Print PDF')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'date', child: Text('Filter by date')),
              PopupMenuItem(value: 'recurring', child: Text('Recurring transactions')),
            ],
          ),
          PopupMenuButton<_SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => _SortOrder.values
                .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
                .toList(),
          ),
          const CurrencySelectorButton(),
          const LogoutButton(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search category, name, or note',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value.toLowerCase()),
            ),
          ),
          if (range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(
                    '${dateFormat.format(range.start)} – ${dateFormat.format(range.end)}',
                  ),
                  onDeleted: () => setState(() => _dateRange = null),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_TypeFilter>(
              segments: const [
                ButtonSegment(value: _TypeFilter.all, label: Text('All')),
                ButtonSegment(value: _TypeFilter.income, label: Text('Income')),
                ButtonSegment(value: _TypeFilter.expense, label: Text('Expense')),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) => setState(() => _filter = selection.first),
            ),
          ),
          GroupFilterChips(
            uid: widget.uid,
            selectedGroupId: _groupFilter,
            onChanged: (value) => setState(() => _groupFilter = value),
          ),
          Expanded(
            child: StreamBuilder<List<Expense>>(
              stream: range != null
                  ? firestore.expensesForRange(
                      widget.uid,
                      accountId,
                      range.start,
                      range.end.add(const Duration(days: 1)),
                    )
                  : firestore.allExpenses(widget.uid, accountId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var transactions = snapshot.data ?? [];
                if (_filter == _TypeFilter.income) {
                  transactions = transactions.where((e) => e.type == TransactionType.income).toList();
                } else if (_filter == _TypeFilter.expense) {
                  transactions = transactions.where((e) => e.type == TransactionType.expense).toList();
                }
                if (_groupFilter != null) {
                  transactions = transactions.where((e) => e.groupId == _groupFilter).toList();
                }
                if (_query.isNotEmpty) {
                  transactions = transactions
                      .where((e) =>
                          e.category.toLowerCase().contains(_query) ||
                          e.note.toLowerCase().contains(_query) ||
                          e.personName.toLowerCase().contains(_query))
                      .toList();
                }

                transactions = [...transactions];
                switch (_sort) {
                  case _SortOrder.dateDesc:
                    transactions.sort((a, b) => b.date.compareTo(a.date));
                    break;
                  case _SortOrder.dateAsc:
                    transactions.sort((a, b) => a.date.compareTo(b.date));
                    break;
                  case _SortOrder.amountDesc:
                    transactions.sort((a, b) => b.amount.compareTo(a.amount));
                    break;
                  case _SortOrder.amountAsc:
                    transactions.sort((a, b) => a.amount.compareTo(b.amount));
                    break;
                }

                _currentTransactions = transactions;

                Widget? groupSummary;
                if (_groupFilter != null && transactions.isNotEmpty) {
                  groupSummary = _GroupTotalBanner(transactions: transactions, currencySymbol: currencySymbol);
                }

                if (transactions.isEmpty) {
                  return const Center(child: Text('No transactions found'));
                }

                final groupByDate = _sort == _SortOrder.dateDesc || _sort == _SortOrder.dateAsc;
                if (!groupByDate) {
                  return Column(
                    children: [
                      if (groupSummary != null) groupSummary,
                      Expanded(
                        child: ListView.builder(
                          itemCount: transactions.length,
                          itemBuilder: (context, index) {
                            final e = transactions[index];
                            final parts = [
                              dateFormat.format(e.date),
                              e.paymentMethod,
                              if (e.personName.isNotEmpty) e.personName,
                              if (e.note.isNotEmpty) e.note,
                            ];
                            return TransactionTile(
                              uid: widget.uid,
                              expense: e,
                              currencySymbol: currencySymbol,
                              subtitleBuilder: (e) => parts.join(' · '),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }

                final grouped = <DateTime, List<Expense>>{};
                for (final t in transactions) {
                  final dayKey = DateTime(t.date.year, t.date.month, t.date.day);
                  grouped.putIfAbsent(dayKey, () => []).add(t);
                }

                // Flatten into a single row list so ListView.builder can lazily
                // build only the rows on screen, instead of the whole history
                // being constructed up front on every rebuild.
                final rows = <_HistoryRow>[];
                for (final entry in grouped.entries) {
                  rows.add(_HistoryRow.header(entry.key, entry.value));
                  for (final e in entry.value) {
                    rows.add(_HistoryRow.transaction(e));
                  }
                }

                return Column(
                  children: [
                    if (groupSummary != null) groupSummary,
                    Expanded(
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          if (row.headerDate != null) {
                            return _DateHeader(
                              date: row.headerDate!,
                              transactions: row.headerTransactions!,
                              currencySymbol: currencySymbol,
                            );
                          }
                          final e = row.expense!;
                          final parts = [
                            e.paymentMethod,
                            if (e.personName.isNotEmpty) e.personName,
                            if (e.note.isNotEmpty) e.note,
                          ];
                          return TransactionTile(
                            uid: widget.uid,
                            expense: e,
                            currencySymbol: currencySymbol,
                            subtitleBuilder: (e) => parts.join(' · '),
                          );
                        },
                      ),
                    ),
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

class _HistoryRow {
  final DateTime? headerDate;
  final List<Expense>? headerTransactions;
  final Expense? expense;

  const _HistoryRow.header(this.headerDate, this.headerTransactions) : expense = null;
  const _HistoryRow.transaction(this.expense)
      : headerDate = null,
        headerTransactions = null;
}

class _GroupTotalBanner extends StatelessWidget {
  final List<Expense> transactions;
  final String currencySymbol;

  const _GroupTotalBanner({required this.transactions, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final income = transactions
        .where((e) => e.type == TransactionType.income)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final expense = transactions
        .where((e) => e.type == TransactionType.expense)
        .fold<double>(0, (sum, e) => sum + e.amount);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${transactions.length} transaction${transactions.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (income > 0)
                Text(
                  '+$currencySymbol${income.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              if (income > 0 && expense > 0) const SizedBox(width: 8),
              if (expense > 0)
                Text(
                  '-$currencySymbol${expense.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final DateTime date;
  final List<Expense> transactions;
  final String currencySymbol;

  const _DateHeader({
    required this.date,
    required this.transactions,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final income = transactions
        .where((e) => e.type == TransactionType.income)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final expense = transactions
        .where((e) => e.type == TransactionType.expense)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(date, now);
    final isYesterday = DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)));
    final label = isToday
        ? 'Today'
        : isYesterday
            ? 'Yesterday'
            : DateFormat('EEEE, MMM d, yyyy').format(date);

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (income > 0)
                Text(
                  '+$currencySymbol${income.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              if (income > 0 && expense > 0) const SizedBox(width: 8),
              if (expense > 0)
                Text(
                  '-$currencySymbol${expense.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
