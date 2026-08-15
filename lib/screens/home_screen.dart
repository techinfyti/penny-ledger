import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../services/category_service.dart';
import '../services/premium_service.dart';
import '../services/purchase_service.dart';
import '../services/recurring_service.dart';
import 'add_expense_screen.dart';
import 'budget_screen.dart';
import 'daily_dashboard.dart';
import 'history_screen.dart';
import 'monthly_dashboard.dart';
import 'yearly_dashboard.dart';

class HomeScreen extends StatefulWidget {
  final String uid;

  const HomeScreen({super.key, required this.uid});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final accountService = context.read<AccountService>();
    context.read<PremiumService>().listen(widget.uid);
    context.read<PurchaseService>().init(widget.uid);
    await accountService.ensureDefaultAccount(widget.uid);
    await accountService.loadSavedAccount();
    // Neither depends on the other or on the account load above (both take
    // just the uid), so run them together instead of back-to-back.
    await Future.wait([
      context.read<CategoryService>().pruneCustomCategoriesMatchingDefaults(widget.uid).catchError((_) {}),
      context.read<RecurringService>().processDueRecurring(widget.uid).catchError((_) {}),
    ]);
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = [
      DailyDashboard(uid: widget.uid),
      MonthlyDashboard(uid: widget.uid),
      YearlyDashboard(uid: widget.uid),
      HistoryScreen(uid: widget.uid),
      BudgetScreen(uid: widget.uid),
    ];

    return Scaffold(
      body: screens[_index],
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddExpenseScreen(uid: widget.uid)),
          );
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Daily'),
          NavigationDestination(icon: Icon(Icons.calendar_view_month), label: 'Monthly'),
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Yearly'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), label: 'Budget'),
        ],
      ),
    );
  }
}
