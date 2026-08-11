import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/recurring_transaction.dart';
import '../services/account_service.dart';
import '../services/budget_service.dart';
import '../services/category_service.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/recurring_service.dart';

const String _addCategorySentinel = '__add_new__';
const String _addGroupSentinel = '__add_group__';
const String _noGroupSentinel = '__no_group__';

class AddExpenseScreen extends StatefulWidget {
  final String uid;
  final Expense? existing;

  const AddExpenseScreen({super.key, required this.uid, this.existing});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _personNameController;
  late TransactionType _type;
  String? _category;
  late DateTime _date;
  late String _paymentMethod;
  String? _groupId;
  bool _repeatMonthly = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amountController = TextEditingController(text: existing != null ? existing.amount.toString() : '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _personNameController = TextEditingController(text: existing?.personName ?? '');
    _type = existing?.type ?? TransactionType.expense;
    _category = existing?.category;
    _date = existing?.date ?? DateTime.now();
    _paymentMethod = existing?.paymentMethod ?? paymentMethods.first;
    _groupId = existing?.groupId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _personNameController.dispose();
    super.dispose();
  }

  void _switchType(TransactionType type) {
    setState(() {
      _type = type;
      _category = null;
    });
  }

  IconData _paymentMethodIcon(String method) {
    switch (method) {
      case 'Cash':
        return Icons.payments_outlined;
      case 'Online':
        return Icons.language;
      case 'Card':
        return Icons.credit_card;
      case 'GPay':
        return Icons.qr_code;
      default:
        return Icons.payment;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _promptNewCategory(List<String> existing) async {
    final categoryService = context.read<CategoryService>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (existing.any((c) => c.toLowerCase() == name.toLowerCase())) {
      setState(() => _category = name);
      return;
    }
    await categoryService.addCategory(widget.uid, _type, name);
    setState(() => _category = name);
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
          decoration: const InputDecoration(labelText: 'Group name (e.g. Family, Friends, Team Trip)'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final id = await groupService.addGroup(widget.uid, name);
    setState(() => _groupId = id);
  }

  Future<void> _checkBudgetAlert(String accountId, String category) async {
    final budgetService = context.read<BudgetService>();
    final firestore = context.read<FirestoreService>();
    final notificationService = context.read<NotificationService>();
    final now = DateTime.now();

    final limit = await budgetService.categoryLimitOnce(widget.uid, accountId, now, category);
    if (limit == null || limit <= 0) return;

    final monthTransactions = await firestore.expensesForMonth(widget.uid, accountId, now).first;
    final spent = monthTransactions
        .where((e) => e.type == TransactionType.expense && e.category == category)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final percent = (spent / limit) * 100;

    final alreadyAlerted = await budgetService.alertedThreshold(widget.uid, accountId, now, category);
    final threshold = percent >= 100 ? 100 : (percent >= 80 ? 80 : null);
    if (threshold == null) return;
    if (alreadyAlerted != null && alreadyAlerted >= threshold) return;

    await budgetService.setAlertedThreshold(widget.uid, accountId, now, category, threshold);
    await notificationService.showBudgetAlert(
      title: threshold == 100 ? 'Budget exceeded: $category' : 'Approaching budget: $category',
      body: threshold == 100
          ? 'You have exceeded your $category budget for this month.'
          : 'You have used ${percent.toStringAsFixed(0)}% of your $category budget for this month.',
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a category')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final firestore = context.read<FirestoreService>();
      final recurringService = context.read<RecurringService>();
      final accountId = widget.existing?.accountId ?? context.read<AccountService>().currentAccountId;
      final expense = Expense(
        id: widget.existing?.id ?? '',
        amount: double.parse(_amountController.text),
        category: _category!,
        date: _date,
        note: _noteController.text.trim(),
        type: _type,
        paymentMethod: _paymentMethod,
        accountId: accountId,
        personName: _personNameController.text.trim(),
        groupId: _groupId,
      );
      if (_isEditing) {
        await firestore.updateExpense(widget.uid, expense);
      } else {
        await firestore.addExpense(widget.uid, expense);
        if (_repeatMonthly) {
          final monthKey = '${_date.year}-${_date.month.toString().padLeft(2, '0')}';
          await recurringService.createRecurring(
            widget.uid,
            RecurringTransaction(
              id: '',
              amount: expense.amount,
              category: expense.category,
              type: expense.type,
              note: expense.note,
              paymentMethod: expense.paymentMethod,
              dayOfMonth: _date.day,
              lastGeneratedMonth: monthKey,
              accountId: accountId,
              personName: expense.personName,
              groupId: expense.groupId,
            ),
          );
        }
      }
      if (_type == TransactionType.expense) {
        await _checkBudgetAlert(accountId, expense.category);
      }
      if (mounted) {
        if (_isEditing) {
          Navigator.of(context).pop();
        } else {
          _amountController.clear();
          _noteController.clear();
          _personNameController.clear();
          setState(() {
            _category = null;
            _date = DateTime.now();
            _paymentMethod = paymentMethods.first;
            _groupId = null;
            _repeatMonthly = false;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_type == TransactionType.income ? 'Income' : 'Expense'} ${_isEditing ? 'updated' : 'added'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryService = context.read<CategoryService>();
    final currencySymbol = context.watch<CurrencyService>().symbol;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Income'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => _switchType(selection.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '$currencySymbol ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Enter an amount';
                  final parsed = double.tryParse(value);
                  if (parsed == null || parsed <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<String>>(
                stream: categoryService.categoriesFor(widget.uid, _type),
                builder: (context, snapshot) {
                  final categories = snapshot.data ?? defaultCategoriesFor(_type);
                  if (_category != null && !categories.contains(_category)) {
                    categories.add(_category!);
                  }
                  return DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(
                        value: _addCategorySentinel,
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 18),
                            SizedBox(width: 8),
                            Text('Add missing category'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == _addCategorySentinel) {
                        _promptNewCategory(categories);
                        return;
                      }
                      setState(() => _category = value);
                    },
                    validator: (value) => value == null ? 'Choose a category' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _personNameController,
                decoration: InputDecoration(
                  labelText: _type == TransactionType.income ? 'Received from (optional)' : 'Paid to (optional)',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<ExpenseGroup>>(
                stream: context.read<GroupService>().groupsFor(widget.uid),
                builder: (context, snapshot) {
                  final groups = snapshot.data ?? [];
                  final validIds = groups.map((g) => g.id).toSet();
                  final currentValue = _groupId != null && validIds.contains(_groupId) ? _groupId : _noGroupSentinel;
                  return DropdownButtonFormField<String>(
                    value: currentValue,
                    decoration: const InputDecoration(
                      labelText: 'Group (optional)',
                      prefixIcon: Icon(Icons.groups_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: _noGroupSentinel, child: Text('No group')),
                      ...groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                      const DropdownMenuItem(
                        value: _addGroupSentinel,
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 18),
                            SizedBox(width: 8),
                            Text('Add new group'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == _addGroupSentinel) {
                        _promptNewGroup();
                        return;
                      }
                      setState(() => _groupId = value == _noGroupSentinel ? null : value);
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
                leading: const Icon(Icons.calendar_today),
                title: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                onTap: _pickDate,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.repeat),
                  title: const Text('Repeat monthly'),
                  subtitle: Text('Auto-add on day ${_date.day} of every month'),
                  value: _repeatMonthly,
                  onChanged: (value) => setState(() => _repeatMonthly = value),
                ),
              ],
              const SizedBox(height: 16),
              Text('Payment method', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: paymentMethods.map((method) {
                  return ChoiceChip(
                    label: Text(method),
                    avatar: Icon(_paymentMethodIcon(method), size: 18),
                    selected: _paymentMethod == method,
                    onSelected: (_) => setState(() => _paymentMethod = method),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isEditing
                      ? 'Update ${_type == TransactionType.income ? 'Income' : 'Expense'}'
                      : 'Save ${_type == TransactionType.income ? 'Income' : 'Expense'}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
