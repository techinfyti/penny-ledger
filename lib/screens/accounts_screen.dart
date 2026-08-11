import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../services/account_service.dart';
import '../services/premium_service.dart';
import 'premium_screen.dart';

class AccountsScreen extends StatelessWidget {
  final String uid;

  const AccountsScreen({super.key, required this.uid});

  Future<void> _addAccount(BuildContext context, int existingCount) async {
    final isPremium = context.read<PremiumService>().isPremium;
    if (existingCount >= 1 && !isPremium) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PremiumScreen(uid: uid)),
      );
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add account'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Account name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (context.mounted) {
      await context.read<AccountService>().addAccount(uid, name);
    }
  }

  Future<void> _renameAccount(BuildContext context, Account account) async {
    final controller = TextEditingController(text: account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename account'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Account name')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == account.name) return;
    if (context.mounted) {
      await context.read<AccountService>().renameAccount(uid, account.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<AccountService>();
    final isPremium = context.watch<PremiumService>().isPremium;

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: StreamBuilder<List<Account>>(
        stream: accountService.accountsFor(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!isPremium)
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium),
                    title: const Text('Go Premium for unlimited accounts'),
                    subtitle: const Text('Free plan is limited to 1 account'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PremiumScreen(uid: uid)),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              ...accounts.map((account) {
                final isCurrent = account.id == accountService.currentAccountId;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      child: Text(account.name.isNotEmpty ? account.name[0].toUpperCase() : '?'),
                    ),
                    title: Text(account.name),
                    subtitle: isCurrent ? const Text('Currently viewing') : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _renameAccount(context, account),
                        ),
                        if (isCurrent) const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                    onTap: () => accountService.setCurrentAccount(account.id),
                  ),
                );
              }),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _addAccount(context, accounts.length),
                icon: const Icon(Icons.add),
                label: const Text('Add account'),
              ),
            ],
          );
        },
      ),
    );
  }
}
