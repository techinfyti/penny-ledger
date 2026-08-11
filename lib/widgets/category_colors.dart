import 'package:flutter/material.dart';
import '../models/expense.dart';

final Map<String, Color> categoryColors = {
  'Food': Colors.orange,
  'Groceries': Colors.lightGreen,
  'Transport': Colors.blue,
  'Fuel': Colors.blueGrey,
  'Bills': Colors.purple,
  'Rent': Colors.brown,
  'Shopping': Colors.pink,
  'Entertainment': Colors.green,
  'Sports': Colors.lightBlueAccent,
  'Fitness': Colors.deepOrangeAccent,
  'Health': Colors.red,
  'Education': Colors.indigo,
  'Travel': Colors.cyan,
  'Insurance': Colors.deepPurple,
  'Subscriptions': Colors.amber,
  'Personal Care': Colors.pinkAccent,
  'Household': Colors.brown,
  'Electronics': Colors.indigoAccent,
  'Gifts & Donations': Colors.purpleAccent,
  'Pets': Colors.orangeAccent,
  'Kids': Colors.tealAccent,
  'Loan/EMI': Colors.redAccent,
  'Maintenance': Colors.grey,
  'Taxes': Colors.blueGrey,
  'Other': Colors.grey,
  'Salary': Colors.teal,
  'Business': Colors.deepOrange,
  'Freelance': Colors.lime,
  'Investment': Colors.lightBlue,
  'Rental Income': Colors.brown,
  'Bonus': Colors.amber,
  'Interest': Colors.cyan,
  'Dividend': Colors.indigo,
  'Cashback': Colors.green,
  'Pension': Colors.deepPurple,
  'Gift': Colors.pinkAccent,
  'Refund': Colors.blueGrey,
  'Other Income': Colors.grey,
};

const List<Color> _fallbackPalette = [
  Colors.teal,
  Colors.orange,
  Colors.blue,
  Colors.purple,
  Colors.green,
  Colors.red,
  Colors.indigo,
  Colors.brown,
  Colors.pink,
  Colors.cyan,
];

Color colorForCategory(String category) {
  final known = categoryColors[category];
  if (known != null) return known;
  final index = category.hashCode.abs() % _fallbackPalette.length;
  return _fallbackPalette[index];
}

Map<String, double> totalsByCategory(Iterable<Expense> expenses) {
  final totals = <String, double>{};
  for (final e in expenses) {
    totals[e.category] = (totals[e.category] ?? 0) + e.amount;
  }
  return totals;
}
