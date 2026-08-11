import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../services/premium_service.dart';
import '../services/purchase_service.dart';

class PremiumScreen extends StatefulWidget {
  final String uid;

  const PremiumScreen({super.key, required this.uid});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  String _selectedPlan = 'lifetime';
  bool _loadingProducts = true;
  List<ProductDetails> _products = [];
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final purchaseService = context.read<PurchaseService>();
    purchaseService.init(widget.uid);
    final products = await purchaseService.queryProducts();
    if (mounted) {
      setState(() {
        _products = products;
        _loadingProducts = false;
      });
    }
  }

  String get _selectedProductId {
    switch (_selectedPlan) {
      case 'monthly':
        return monthlyProductId;
      case 'five_year':
        return fiveYearProductId;
      default:
        return lifetimeProductId;
    }
  }

  String get _unlockButtonLabel {
    switch (_selectedPlan) {
      case 'monthly':
        return 'Start Monthly Plan';
      case 'five_year':
        return 'Unlock 5 Year Access';
      default:
        return 'Unlock Lifetime Access';
    }
  }

  Future<void> _restore() async {
    final purchaseService = context.read<PurchaseService>();
    setState(() => _restoring = true);
    try {
      await purchaseService.restore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checked for past purchases.')),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _unlock() async {
    final purchaseService = context.read<PurchaseService>();
    final productId = _selectedProductId;
    ProductDetails? product;
    for (final p in _products) {
      if (p.id == productId) {
        product = p;
        break;
      }
    }
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Purchases aren't set up on the Play Store yet. Check back soon!")),
      );
      return;
    }
    setState(() => _purchasing = true);
    try {
      await purchaseService.buy(product);
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: scheme.primary.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(Icons.workspace_premium, size: 40, color: scheme.primary),
              ),
              const SizedBox(height: 16),
              if (isPremium) ...[
                const Text("You're Premium!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Thanks for supporting PennyLedger.', textAlign: TextAlign.center),
              ] else ...[
                const Text('Go Premium', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Unlock multiple accounts, cloud backup & an ad-free experience',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 28),
                const _FeatureTable(),
                const SizedBox(height: 24),
                _loadingProducts
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          _PlanTile(
                            label: 'Lifetime',
                            price: '₹1,999.00',
                            badge: 'Most Popular',
                            selected: _selectedPlan == 'lifetime',
                            onTap: () => setState(() => _selectedPlan = 'lifetime'),
                          ),
                          const SizedBox(height: 12),
                          _PlanTile(
                            label: '5 Years',
                            price: '₹1,499.00',
                            selected: _selectedPlan == 'five_year',
                            onTap: () => setState(() => _selectedPlan = 'five_year'),
                          ),
                          const SizedBox(height: 12),
                          _PlanTile(
                            label: 'Monthly',
                            price: '₹99.00',
                            selected: _selectedPlan == 'monthly',
                            onTap: () => setState(() => _selectedPlan = 'monthly'),
                          ),
                        ],
                      ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _purchasing ? null : _unlock,
                    child: _purchasing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_unlockButtonLabel),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'To cancel anytime, please visit your Google Play Store setting.\n'
                  'Subscription automatically renews unless auto renew is cancelled at least 24 hours before the last date.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    const Text('Privacy Policy', style: TextStyle(fontSize: 11)),
                    const Text('·'),
                    const Text('Terms of use', style: TextStyle(fontSize: 11)),
                    const Text('·'),
                    GestureDetector(
                      onTap: _restoring ? null : _restore,
                      child: Text(
                        _restoring ? 'Restoring…' : 'Restore',
                        style: const TextStyle(fontSize: 11, decoration: TextDecoration.underline),
                      ),
                    ),
                    const Text('·'),
                    const Text('How to Cancel', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTable extends StatelessWidget {
  const _FeatureTable();

  static const List<String> _rows = [
    'Multiple Accounts',
    'Cloud Backup & Restore',
    'CSV Export',
    'Ad-Free Experience',
    'Priority Support',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(flex: 3, child: SizedBox()),
            Expanded(
              flex: 1,
              child: Text('Basic', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 1,
              child: Text('Premium', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final label in _rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text(label)),
                const Expanded(flex: 1, child: Icon(Icons.remove, size: 18, color: Colors.grey)),
                const Expanded(flex: 1, child: Icon(Icons.check, size: 18, color: Colors.green)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  final String label;
  final String price;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanTile({
    required this.label,
    required this.price,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
          color: selected ? scheme.primary.withOpacity(0.06) : null,
        ),
        child: Row(
          children: [
            Radio<bool>(value: true, groupValue: selected ? true : null, onChanged: (_) => onTap()),
            Expanded(child: Text('$label :', style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(price, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(20)),
                child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
