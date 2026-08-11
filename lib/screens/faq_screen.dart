import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const List<(String, String)> _faqs = [
    (
      'How do I log in to PennyLedger?',
      'Open the app and tap "Sign in with Google," then choose your Google account. Your data syncs automatically to that account, so signing in with the same Google account on any device brings back your transactions.',
    ),
    (
      'What\'s the difference between Accounts and Groups?',
      'Accounts are separate ledgers (e.g. Personal vs Business) with their own transactions, budgets, and recurring items. Groups are a lighter-weight tag (e.g. Family, Friends, Team) you can attach to any transaction within an account to see totals for just that group.',
    ),
    (
      'What does Premium unlock?',
      'Premium unlocks unlimited accounts, Google Drive backup & restore, CSV export, an ad-free experience, and priority support. Go to Settings → Upgrade to Premium to see current pricing.',
    ),
    (
      'How do I back up my data?',
      'Go to Settings → Backup to Google Drive (Premium feature). Your transactions, categories, budgets, and recurring items are saved to your own Google Drive. Restore brings everything back from your last backup.',
    ),
    (
      'How do I change the currency?',
      'Tap the currency button in any dashboard\'s app bar (shows your currency code, e.g. INR) and pick from the full list of supported currencies.',
    ),
    (
      'Can I add my own categories?',
      'Yes. When adding a transaction, choose "Add missing category" from the Category dropdown. You can rename categories you\'ve added under Settings → Manage Categories.',
    ),
    (
      'How do recurring transactions work?',
      'When adding a transaction, turn on "Repeat monthly" to create a template. It automatically adds a new transaction on the same day every month. Manage or delete templates from the repeat icon in History.',
    ),
    (
      'How do budget alerts work?',
      'Set a monthly limit for a category under the Budget tab. You\'ll get a notification when your spending crosses 80% and 100% of that limit.',
    ),
    (
      'Is my app lock the same as my phone lock?',
      'No, it\'s a separate layer. Enable App Lock in Settings to require your device\'s fingerprint, face, or PIN every time you open PennyLedger, on top of your regular phone lock screen.',
    ),
    (
      'How do I export my transactions?',
      'PDF export/print is available from any dashboard\'s PDF icon. CSV export (Premium) is available from the History tab.',
    ),
    (
      'Can I change the app\'s color theme?',
      'Yes. Go to Settings → Theme Color to choose from Blue, Green, Purple, Orange, Red, or Teal.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FAQ')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _faqs.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final (question, answer) = _faqs[index];
          return ExpansionTile(
            title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(answer, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
            ],
          );
        },
      ),
    );
  }
}
