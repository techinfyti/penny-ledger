import '../../models/expense.dart';
import 'imported_transaction.dart';

/// Reads the text of a Google Pay "Transaction statement" PDF.
///
/// Each entry looks like: date, time, "Paid to <name>" or "Received from
/// <name>", "UPI Transaction ID: <id>", an account line, then the amount.
class GpayPdfParser {
  static final _date = RegExp(r'^(\d{1,2})\s*([A-Za-z]{3})[A-Za-z]*,?\s*(\d{4})$');
  static final _time = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$');
  static final _amount = RegExp(r'^₹\s*([\d,]+(?:\.\d+)?)$');
  static final _detail = RegExp(r'^(Received from|Paid to)\s*(.*)$', caseSensitive: false);
  static final _ref = RegExp(r'UPI Transaction ID:\s*(\d+)', caseSensitive: false);
  static final _skip = RegExp(r'^(Page\s*\d+\s*of\s*\d+|Note:|received\.|Transaction statement|Date\s*&)', caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static bool looksLikeGpay(String text) {
    return text.contains('UPI Transaction ID') && RegExp(r'Transaction\s*statement', caseSensitive: false).hasMatch(text);
  }

  static double _money(String raw) => double.parse(raw.replaceAll(',', ''));

  static ParsedStatement parse(List<String> rawLines) {
    final lines = rawLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    double? sent;
    double? received;
    for (var i = 0; i < lines.length - 1; i++) {
      final next = _amount.firstMatch(lines[i + 1]);
      if (next == null) continue;
      if (lines[i] == 'Sent' && sent == null) sent = _money(next.group(1)!);
      if (lines[i] == 'Received' && received == null) received = _money(next.group(1)!);
    }

    final items = <ImportedTransaction>[];
    var i = 0;
    while (i < lines.length) {
      final dateMatch = _date.firstMatch(lines[i]);
      final timeMatch = i + 1 < lines.length ? _time.firstMatch(lines[i + 1]) : null;
      if (dateMatch == null || timeMatch == null) {
        i++;
        continue;
      }

      final month = _months[dateMatch.group(2)!.toLowerCase()];
      var j = i + 2;
      final block = <String>[];
      while (j < lines.length && !_amount.hasMatch(lines[j]) && !(_date.hasMatch(lines[j]) && j + 1 < lines.length && _time.hasMatch(lines[j + 1]))) {
        if (!_skip.hasMatch(lines[j])) block.add(lines[j]);
        j++;
      }
      final amountMatch = j < lines.length ? _amount.firstMatch(lines[j]) : null;
      if (amountMatch != null) j++;

      final detail = block.isEmpty ? null : _detail.firstMatch(block.first);
      if (month != null && detail != null && amountMatch != null) {
        var hour = int.parse(timeMatch.group(1)!) % 12;
        if (timeMatch.group(3)!.toLowerCase() == 'pm') hour += 12;
        final ref = block.map(_ref.firstMatch).whereType<RegExpMatch>().map((m) => m.group(1)!).firstOrNull;
        final isIncome = detail.group(1)!.toLowerCase() == 'received from';
        items.add(ImportedTransaction(
          date: DateTime(
            int.parse(dateMatch.group(3)!),
            month,
            int.parse(dateMatch.group(1)!),
            hour,
            int.parse(timeMatch.group(2)!),
          ),
          description: detail.group(2)!.trim(),
          amount: _money(amountMatch.group(1)!),
          type: isIncome ? TransactionType.income : TransactionType.expense,
          upiRef: ref,
          paymentMethod: 'GPay',
        ));
      }
      i = j > i ? j : i + 1;
    }

    return ParsedStatement(
      sourceLabel: 'Google Pay statement',
      items: items,
      statedExpenseTotal: sent,
      statedIncomeTotal: received,
    );
  }
}
