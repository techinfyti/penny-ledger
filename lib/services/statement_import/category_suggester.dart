import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/expense.dart';

/// Suggests a category from a payee or narration. Choices the user makes are
/// remembered per payee, so repeat payees are filled in next time.
class CategorySuggester {
  static const _prefsKey = 'import_payee_categories';

  static final List<MapEntry<RegExp, String>> _expenseRules = [
    _rule(r'swiggy|zomato|domino|kfc|mcdonald|pizza|burger|restaurant|cafe|biryani|bakery|dhaba|sweets|juice|tea\b|food', 'Food'),
    _rule(r'bigbasket|blinkit|zepto|dmart|instamart|grocer|supermarket|provision|vegetable|fruit|milk|fresh', 'Groceries'),
    _rule(r'\bola\b|uber|rapido|metro|\bbus\b|\bauto\b|\bcab\b|parking|fastag|toll', 'Transport'),
    _rule(r'petrol|fuel|hpcl|bpcl|iocl|indian oil|shell|\bpump\b', 'Fuel'),
    _rule(r'electric|tneb|bescom|water|\bgas\b|broadband|airtel|\bjio\b|vodafone|\bvi\b|recharge|bsnl|\bdth\b|tata play|postpaid|bill', 'Bills'),
    _rule(r'netflix|spotify|hotstar|prime video|youtube|google play|apple|subscription', 'Subscriptions'),
    _rule(r'bookmyshow|\bpvr\b|inox|movie|cinema', 'Entertainment'),
    _rule(r'amazon|flipkart|myntra|ajio|meesho|nykaa|\bmall\b|\bstore\b|\bmart\b|shopping', 'Shopping'),
    _rule(r'pharmacy|apollo|medplus|hospital|clinic|medical|1mg|pharmeasy|diagnostic|\blab\b', 'Health'),
    _rule(r'school|college|tuition|course|udemy|byju|\bfees?\b|academy', 'Education'),
    _rule(r'irctc|redbus|makemytrip|goibibo|flight|indigo|airlines|oyo|ticket', 'Travel'),
    _rule(r'insurance|\blic\b|policy|premium', 'Insurance'),
    _rule(r'\bemi\b|\bloan\b|bajaj finance', 'Loan/EMI'),
    _rule(r'\brent\b|landlord', 'Rent'),
    _rule(r'donation|temple|\btrust\b|charity|gift', 'Gifts & Donations'),
    _rule(r'salon|parlour|spa\b|barber|beauty', 'Personal Care'),
    _rule(r'hardware|furniture|plumber|electrician|repair', 'Household'),
    _rule(r'income tax|\bgst\b|\btax\b', 'Taxes'),
  ];

  static final List<MapEntry<RegExp, String>> _incomeRules = [
    _rule(r'salary|payroll|wages', 'Salary'),
    _rule(r'interest', 'Interest'),
    _rule(r'dividend', 'Dividend'),
    _rule(r'refund|reversal|reversed', 'Refund'),
    _rule(r'cashback|reward', 'Cashback'),
    _rule(r'bonus', 'Bonus'),
    _rule(r'rent', 'Rental Income'),
  ];

  static MapEntry<RegExp, String> _rule(String pattern, String category) {
    return MapEntry(RegExp(pattern, caseSensitive: false), category);
  }

  static String normalise(String payee) {
    return payee.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String suggest(String description, TransactionType type, {Map<String, String> memory = const {}}) {
    final remembered = memory[normalise(description)];
    if (remembered != null) return remembered;
    final rules = type == TransactionType.income ? _incomeRules : _expenseRules;
    for (final rule in rules) {
      if (rule.key.hasMatch(description)) return rule.value;
    }
    return type == TransactionType.income ? 'Other Income' : 'Other';
  }

  static Future<Map<String, String>> loadMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveMemory(Map<String, String> additions) async {
    if (additions.isEmpty) return;
    final memory = await loadMemory();
    memory.addAll(additions);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(memory));
  }
}
