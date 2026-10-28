import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Lets the user pick a month and year; returns the first day of that month.
Future<DateTime?> pickMonth(BuildContext context, DateTime initial, {int yearsBack = 5, int yearsAhead = 2}) {
  final thisYear = DateTime.now().year;
  var year = initial.year;
  return showDialog<DateTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: year > thisYear - yearsBack ? () => setState(() => year--) : null,
            ),
            Text('$year'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: year < thisYear + yearsAhead ? () => setState(() => year++) : null,
            ),
          ],
        ),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var m = 1; m <= 12; m++)
                ChoiceChip(
                  label: Text(DateFormat('MMM').format(DateTime(2000, m))),
                  selected: year == initial.year && m == initial.month,
                  onSelected: (_) => Navigator.of(context).pop(DateTime(year, m)),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
      ),
    ),
  );
}
