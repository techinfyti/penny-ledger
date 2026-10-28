import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../services/account_service.dart';
import '../services/category_service.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../services/group_service.dart';
import '../services/premium_service.dart';
import '../services/statement_import/category_suggester.dart';
import '../services/statement_import/imported_transaction.dart';
import '../services/statement_import/statement_reader.dart';
import 'premium_screen.dart';

/// Import Transactions is a Premium feature: free users land on the Premium screen.
void openStatementImport(BuildContext context, String uid) {
  final isPremium = context.read<PremiumService>().isPremium;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => isPremium ? StatementImportScreen(uid: uid) : PremiumScreen(uid: uid)),
  );
}

const String _addGroupSentinel = '__add_group__';
const String _noGroupSentinel = '__no_group__';

class StatementImportScreen extends StatefulWidget {
  final String uid;

  const StatementImportScreen({super.key, required this.uid});

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  bool _busy = false;
  String? _error;
  ParsedStatement? _parsed;
  List<String> _expenseCategories = defaultExpenseCategories;
  List<String> _incomeCategories = defaultIncomeCategories;
  String? _groupId;
  int? _importedCount;
  int _skippedCount = 0;

  Future<void> _pick() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'csv', 'xlsx', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Couldn\'t open that file. Try another one.');
      return;
    }
    await _load(file.name, bytes);
  }

  Future<void> _load(String name, List<int> rawBytes,
      {String? password}) async {
    final bytes =
        rawBytes is Uint8List ? rawBytes : Uint8List.fromList(rawBytes);
    setState(() {
      _busy = true;
      _error = null;
    });
    // Let the spinner paint before the (synchronous) PDF parsing starts.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final parsed = await StatementReader.read(
          fileName: name, bytes: bytes, pdfPassword: password);
      await _prepare(parsed);
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _busy = false;
      });
    } on StatementPasswordRequired catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final entered = await _askPassword(wrong: e.wrongPassword);
      if (entered != null && entered.isNotEmpty && mounted) {
        await _load(name, bytes, password: entered);
      }
    } on StatementFormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Couldn\'t read this file. Check that it\'s a statement and try again.';
      });
    }
  }

  Future<String?> _askPassword({required bool wrong}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(wrong
                ? 'That password is wrong. Try again.'
                : 'This statement is password protected.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Password', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Open')),
        ],
      ),
    );
  }

  Future<void> _prepare(ParsedStatement parsed) async {
    final categoryService = context.read<CategoryService>();
    final firestore = context.read<FirestoreService>();
    final accountId = context.read<AccountService>().currentAccountId;

    try {
      _expenseCategories = await categoryService
          .categoriesFor(widget.uid, TransactionType.expense)
          .first
          .timeout(const Duration(seconds: 4));
      _incomeCategories = await categoryService
          .categoriesFor(widget.uid, TransactionType.income)
          .first
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      _expenseCategories = defaultExpenseCategories;
      _incomeCategories = defaultIncomeCategories;
    }


    final memory = await CategorySuggester.loadMemory();
    for (final item in parsed.items) {
      final allowed = item.isIncome ? _incomeCategories : _expenseCategories;
      final fromFile = item.category;
      item.category = allowed.contains(fromFile)
          ? fromFile
          : CategorySuggester.suggest(item.description, item.type,
              memory: memory);
      if (!allowed.contains(item.category))
        item.category = item.isIncome ? 'Other Income' : 'Other';
    }

    final dates = parsed.items.map((t) => t.date).toList()..sort();
    final start =
        DateTime(dates.first.year, dates.first.month, dates.first.day);
    final end = DateTime(dates.last.year, dates.last.month, dates.last.day)
        .add(const Duration(days: 1));
    try {
      final existing = await firestore
          .expensesForRange(widget.uid, accountId, start, end)
          .first
          .timeout(const Duration(seconds: 8));
      final refs = existing.map((e) => e.upiRef).whereType<String>().toSet();
      final keys = existing.map(_key).toSet();
      for (final item in parsed.items) {
        final byRef = item.upiRef != null && refs.contains(item.upiRef);
        final byKey = keys.contains(
            '${DateFormat('yyyy-MM-dd').format(item.date)}|${item.amount.toStringAsFixed(2)}|${item.type.field}');
        item.duplicate = byRef || byKey;
        item.selected = !item.duplicate;
      }
    } catch (_) {
      // If the check can't run, keep everything selected; the review screen still lets the user untick rows.
    }
  }

  String _key(Expense e) =>
      '${DateFormat('yyyy-MM-dd').format(e.date)}|${e.amount.toStringAsFixed(2)}|${e.type.field}';

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final firestore = context.read<FirestoreService>();
    final accountId = context.read<AccountService>().currentAccountId;
    final chosen = parsed.items.where((t) => t.selected).toList();
    if (chosen.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await firestore.addExpenses(
        widget.uid,
        chosen
            .map((t) => Expense(
                  id: '',
                  amount: t.amount,
                  category: t.category,
                  date: t.date,
                  note: t.description,
                  type: t.type,
                  paymentMethod: t.paymentMethod,
                  groupId: _groupId,
                  accountId: accountId,
                  upiRef: t.upiRef,
                ))
            .toList(),
      );
      await CategorySuggester.saveMemory({
        for (final t in chosen)
          if (t.category != 'Other' && t.category != 'Other Income')
            CategorySuggester.normalise(t.description): t.category,
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _importedCount = chosen.length;
        _skippedCount = parsed.items.length - chosen.length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Couldn\'t save the transactions. Check your connection and try again.';
      });
    }
  }

  Future<void> _promptNewGroup() async {
    final groupService = context.read<GroupService>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Group name (e.g. Family, Friends, Team Trip)'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final id = await groupService.addGroup(widget.uid, name);
    if (mounted) setState(() => _groupId = id);
  }

  Widget _importSettings(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Group for all imported transactions',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          StreamBuilder<List<ExpenseGroup>>(
            stream: context.read<GroupService>().groupsFor(widget.uid),
            builder: (context, snapshot) {
              final groups = snapshot.data ?? [];
              final validIds = groups.map((g) => g.id).toSet();
              final current = _groupId != null && validIds.contains(_groupId)
                  ? _groupId
                  : _noGroupSentinel;
              return DropdownButtonFormField<String>(
                value: current,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Group (optional)',
                  prefixIcon: Icon(Icons.groups_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: _noGroupSentinel, child: Text('No group')),
                  ...groups.map((g) =>
                      DropdownMenuItem(value: g.id, child: Text(g.name))),
                  const DropdownMenuItem(
                    value: _addGroupSentinel,
                    child: Row(children: [
                      Icon(Icons.add, size: 18),
                      SizedBox(width: 8),
                      Text('Add new group')
                    ]),
                  ),
                ],
                onChanged: (value) {
                  if (value == _addGroupSentinel) {
                    _promptNewGroup();
                    return;
                  }
                  setState(() =>
                      _groupId = value == _noGroupSentinel ? null : value);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _setAll(bool value) {
    final parsed = _parsed;
    if (parsed == null) return;
    setState(() {
      for (final t in parsed.items) {
        t.selected = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Transactions')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _importedCount != null
              ? _buildDone(context)
              : _parsed != null
                  ? _buildReview(context, _parsed!)
                  : _buildStart(context),
    );
  }

  Widget _buildStart(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        Icon(Icons.upload_file,
            size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text('Import transactions',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Add many transactions at once from a Google Pay statement (PDF) or a bank or Paytm statement (CSV or Excel).',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8)),
            child: Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer)),
          ),
        FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose file')),
        const SizedBox(height: 20),
        _hint(context, Icons.picture_as_pdf_outlined,
            'Google Pay: open Show transaction history, tap the download icon, and pick a date range.'),
        _hint(context, Icons.table_chart_outlined,
            'Banks and Paytm: download the statement as CSV or Excel (.xlsx) from the app or net banking. Older .xls files: save as .xlsx or CSV first.'),
        _hint(context, Icons.lock_outline,
            'Your file is read on your phone. Nothing is saved until you tap Import.'),
      ],
    );
  }

  Widget _hint(BuildContext context, IconData icon, String text) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: muted))),
        ],
      ),
    );
  }

  Widget _buildReview(BuildContext context, ParsedStatement parsed) {
    final symbol = context.watch<CurrencyService>().symbol;
    final money = NumberFormat('#,##0.00');
    final selected = parsed.items.where((t) => t.selected).length;
    final expenses = parsed.items.where((t) => !t.isIncome).length;
    final incomeCount = parsed.items.length - expenses;
    final match = parsed.totalsMatch;
    final scheme = Theme.of(context).colorScheme;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(parsed.sourceLabel,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${parsed.items.length} transactions: $expenses expenses ($symbol${money.format(parsed.expenseTotal)}), '
            '$incomeCount income ($symbol${money.format(parsed.incomeTotal)})',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          if (match != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: match
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.orange.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                      match
                          ? Icons.verified_outlined
                          : Icons.warning_amber_rounded,
                      size: 18,
                      color: match
                          ? Colors.green.shade800
                          : Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      match
                          ? 'Totals match the statement'
                          : 'Totals don\'t match the statement ($symbol${money.format(parsed.statedExpenseTotal ?? 0)} sent, '
                              '$symbol${money.format(parsed.statedIncomeTotal ?? 0)} received). Check the list before importing.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
          ],
          _importSettings(context),
          Row(
            children: [
              TextButton(
                  onPressed: () => _setAll(true),
                  child: const Text('Select all')),
              TextButton(
                  onPressed: () => _setAll(false),
                  child: const Text('Select none')),
            ],
          ),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: parsed.items.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) return header;
              return _row(context, parsed.items[index - 1], symbol, money);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selected == 0 ? null : _import,
                child: Text('Import $selected transactions'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ImportedTransaction t, String symbol,
      NumberFormat money) {
    final scheme = Theme.of(context).colorScheme;
    final categories = t.isIncome ? _incomeCategories : _expenseCategories;
    final options = categories.contains(t.category)
        ? categories
        : [...categories, t.category];
    final color = t.isIncome ? Colors.green.shade700 : Colors.red.shade700;

    return InkWell(
      onTap: () => setState(() => t.selected = !t.selected),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            Checkbox(
                value: t.selected,
                onChanged: (v) => setState(() => t.selected = v ?? false)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.description.isEmpty ? '(no details)' : t.description,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(DateFormat('MMM d, yyyy').format(t.date),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      if (t.duplicate) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('Already added',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange.shade900)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${t.isIncome ? '+' : '-'}$symbol${money.format(t.amount)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                DropdownButton<String>(
                  value: t.category,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  items: options
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => t.category = value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade600),
            const SizedBox(height: 12),
            Text('$_importedCount transactions imported',
                style: Theme.of(context).textTheme.titleLarge),
            if (_skippedCount > 0) ...[
              const SizedBox(height: 6),
              Text('$_skippedCount skipped', style: TextStyle(color: muted)),
            ],
            const SizedBox(height: 20),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
