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
      'Premium unlocks unlimited accounts, Google Drive backup & restore, CSV export, Import Transactions (from Google Pay, bank and Paytm statements), an ad-free experience, and priority support. Go to Settings → Upgrade to Premium to see current pricing.',
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
      'Set a monthly limit for a category under the Budget tab. You\'ll get a notification when your spending crosses 80% and 100% of that limit for that month.',
    ),
    (
      'Where are Settings and the ⋮ menu?',
      'The Settings icon (⚙) is in the top bar of every tab: Daily, Monthly, Yearly, History and Budget. The ⋮ menu on Daily, Monthly, Yearly and History has Import Transactions, Download / Share PDF, Print PDF, Export CSV and Recurring transactions. History\'s ⋮ menu also has Filter by date.',
    ),
    (
      'How do I import transactions from a statement? (Premium)',
      'Import Transactions is a Premium feature. Tap ⋮ → Import Transactions on Daily, Monthly, Yearly or History, then Choose file. PennyLedger reads the file on your phone and shows every transaction with a tick box, its category and the amount. Untick anything you don\'t want, change categories if needed, optionally choose a Group, and tap Import. Nothing is saved until you tap Import.',
    ),
    (
      'Which statements can I import?',
      '• Google Pay: the PDF "Transaction statement" (Google Pay → Show transaction history → download icon → pick the dates). Totals are checked against the totals printed on the statement.\n'
          '• HDFC Bank or Axis Bank savings account statement (PDF) from net banking or the app. If the PDF is password protected, the app asks for the password. Other banks\' PDFs (such as ICICI or Canara) are read on a best-effort basis: check the banner on the review screen, which tells you if the amounts match the statement\'s balances. If it doesn\'t, or the PDF is refused, use the bank\'s CSV or Excel download instead.\n'
          '• Banks: the CSV or Excel (.xlsx) statement from net banking or your bank\'s app. It needs a Date column and either Debit / Credit columns or one Amount column.\n'
          '• Paytm: the CSV or Excel statement downloaded from Paytm.\n'
          '• PhonePe, BHIM, Amazon Pay and other UPI apps: their PDF statements are not supported yet. Use your bank\'s CSV or Excel statement instead, which includes those UPI payments.\n'
          '• Old .xls files: open the file in Excel and save it as .xlsx or CSV first. Password-protected PDFs are supported: the app asks for the password.',
    ),
    (
      'How are imported transactions recorded?',
      'Money sent or debited becomes an expense, and money received or credited becomes income. The payment method is GPay for Google Pay statements and Online for bank and Paytm files. Categories are suggested from the shop or person\'s name, and you can change any of them before importing. PennyLedger remembers the category you pick for each name and uses it next time. Transactions go into the account you currently have selected.',
    ),
    (
      'Can I put imported transactions into a group?',
      'Yes. On the review screen, choose a Group (or tap Add new group) and every imported transaction gets that group. If one statement belongs to different groups, untick the rows that don\'t belong, import, then import again with the other group.',
    ),
    (
      'Will importing the same statement twice create duplicates?',
      'No. Transactions that are already in your account, matched by UPI reference or by the same date, amount and type, are marked "Already added" and left unticked.',
    ),
    (
      'How do monthly budgets work?',
      'Every month has its own limits. On the Budget tab, use the ‹ › arrows or tap the month name to look at any earlier or later month; the totals, chart and categories change with it. To set or change a limit, tap Set Limit or Edit on a category, enter the amount and choose the month in the same box.',
    ),
    (
      'How do I copy last month\'s budget?',
      'Open the Budget tab, go to the month you want to fill, and tap the "Copy (previous month)\'s budget" button above the category list. All limits from the previous month are copied. Limits you have already set in this month are kept, not overwritten.',
    ),
    (
      'How do I remove a budget limit?',
      'Tap Edit on the category, then Remove limit. It only clears that category for the month you are viewing; other months are not affected.',
    ),
    (
      'Is my app lock the same as my phone lock?',
      'No, it\'s a separate layer. Enable App Lock in Settings to require your device\'s fingerprint, face, or PIN every time you open PennyLedger, on top of your regular phone lock screen.',
    ),
    (
      'How do I export my transactions?',
      'Tap the ⋮ menu at the top of Daily, Monthly, Yearly or History. Download / Share PDF and Print PDF cover the day, month or year you are viewing (or the filtered list in History). Export CSV is a Premium feature and works the same way.',
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
