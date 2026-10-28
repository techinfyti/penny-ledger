import '../../models/expense.dart';
import 'imported_transaction.dart';

/// Reads bank, Paytm and Penny Ledger CSV exports by finding the header row
/// and matching columns by name, so no fixed layout is needed.
class CsvStatementParser {
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static ParsedStatement parse(String rawText) {
    final text = rawText.startsWith('﻿') ? rawText.substring(1) : rawText;
    return parseRows(_splitRows(text, _detectDelimiter(text)), sourceLabel: 'CSV statement');
  }

  /// Shared by CSV and Excel files: both end up as plain rows of text cells.
  static ParsedStatement parseRows(List<List<String>> rows, {required String sourceLabel}) {
    var headerIndex = -1;
    _Columns? cols;
    for (var i = 0; i < rows.length && i < 80; i++) {
      final candidate = _Columns.fromHeader(rows[i]);
      if (candidate != null) {
        headerIndex = i;
        cols = candidate;
        break;
      }
    }
    if (cols == null) {
      throw StatementFormatException(
        'Couldn\'t find the columns. The file needs a header row with a date and an amount (or debit and credit).',
      );
    }

    final items = <ImportedTransaction>[];
    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      String cell(int? index) => index != null && index < row.length ? row[index].trim() : '';

      final date = parseDate(cell(cols.date));
      if (date == null) continue;

      var isIncome = false;
      double? amount;
      final debit = parseNumber(cell(cols.debit));
      final credit = parseNumber(cell(cols.credit));
      if (cols.debit != null || cols.credit != null) {
        if (debit != null && debit.abs() > 0) {
          amount = debit.abs();
        } else if (credit != null && credit.abs() > 0) {
          amount = credit.abs();
          isIncome = true;
        }
      }
      if (amount == null && cols.amount != null) {
        final raw = cell(cols.amount);
        final value = parseNumber(raw);
        if (value != null && value != 0) {
          amount = value.abs();
          final hint = '${cell(cols.type)} ${raw.replaceAll(RegExp(r'[\d.,\s]'), '')}'.toLowerCase();
          if (RegExp(r'\b(cr|credit|income|received|deposit)\b|\+').hasMatch(hint)) {
            isIncome = true;
          } else if (RegExp(r'\b(dr|debit|expense|paid|withdrawal)\b').hasMatch(hint) || value < 0 || raw.contains('-')) {
            isIncome = false;
          }
        }
      }
      if (amount == null) continue;

      var description = cell(cols.description);
      if (description.isEmpty) {
        description = row.where((c) => c.trim().isNotEmpty && parseNumber(c) == null && parseDate(c) == null).join(' ').trim();
      }
      var ref = cell(cols.reference);
      if (ref.isEmpty) {
        ref = RegExp(r'(?<!\d)\d{12}(?!\d)').firstMatch(description)?.group(0) ?? '';
      }
      final importedCategory = cell(cols.category);

      items.add(ImportedTransaction(
        date: date,
        description: description,
        amount: amount,
        type: isIncome ? TransactionType.income : TransactionType.expense,
        upiRef: ref.isEmpty ? null : ref,
        category: importedCategory,
      ));
    }

    if (items.isEmpty) {
      throw StatementFormatException('No transactions found in this file.');
    }
    return ParsedStatement(sourceLabel: sourceLabel, items: items);
  }

  static String _detectDelimiter(String text) {
    final sample = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).take(6).toList();
    var best = ',';
    var bestScore = 0;
    for (final d in [',', ';', '\t', '|']) {
      final score = sample.fold<int>(0, (sum, l) => sum + d.allMatches(l).length);
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best;
  }

  static List<List<String>> _splitRows(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    row.add(field.toString());
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  static double? parseNumber(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final negative = s.startsWith('(') && s.endsWith(')') || s.contains('-');
    s = s.replaceAll(RegExp(r'rs\.?|inr|₹', caseSensitive: false), '').replaceAll(RegExp(r'[^0-9.]'), '');
    if (s.isEmpty || s == '.') return null;
    final value = double.tryParse(s);
    if (value == null) return null;
    return negative ? -value : value;
  }

  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    int? year, month, day;
    var rest = '';

    var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(.*)$').firstMatch(s);
    if (m != null) {
      year = int.parse(m.group(1)!);
      month = int.parse(m.group(2)!);
      day = int.parse(m.group(3)!);
      rest = m.group(4)!;
    } else if ((m = RegExp(r'^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{2,4})(.*)$').firstMatch(s)) != null) {
      day = int.parse(m!.group(1)!);
      month = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
      rest = m.group(4)!;
    } else if ((m = RegExp(r'^(\d{1,2})[-/. ]+([A-Za-z]{3})[A-Za-z]*[-/. ,]+(\d{2,4})(.*)$').firstMatch(s)) != null) {
      day = int.parse(m!.group(1)!);
      month = _months[m.group(2)!.toLowerCase()];
      year = int.parse(m.group(3)!);
      rest = m.group(4)!;
    } else if ((m = RegExp(r'^([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{1,2}),?\s+(\d{4})(.*)$').firstMatch(s)) != null) {
      month = _months[m!.group(1)!.toLowerCase()];
      day = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
      rest = m.group(4)!;
    }
    if (year == null || month == null || day == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000 || year > 2100) return null;

    var hour = 0;
    var minute = 0;
    final t = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?').firstMatch(rest);
    if (t != null) {
      hour = int.parse(t.group(1)!);
      minute = int.parse(t.group(2)!);
      final ampm = t.group(3)?.toLowerCase();
      if (ampm != null) {
        hour %= 12;
        if (ampm == 'pm') hour += 12;
      }
      if (hour > 23 || minute > 59) {
        hour = 0;
        minute = 0;
      }
    }
    final result = DateTime(year, month, day, hour, minute);
    return result.month == month ? result : null;
  }
}

class _Columns {
  final int? date;
  final int? description;
  final int? debit;
  final int? credit;
  final int? amount;
  final int? type;
  final int? reference;
  final int? category;

  _Columns({this.date, this.description, this.debit, this.credit, this.amount, this.type, this.reference, this.category});

  static int? _find(List<String> header, List<String> exact, List<String> contains) {
    for (var i = 0; i < header.length; i++) {
      if (exact.contains(header[i])) return i;
    }
    for (var i = 0; i < header.length; i++) {
      if (contains.any(header[i].contains)) return i;
    }
    return null;
  }

  static _Columns? fromHeader(List<String> row) {
    final h = row.map((c) => c.trim().toLowerCase()).toList();
    final date = _find(h, ['date', 'txn date', 'transaction date', 'value date', 'posting date'], ['date']);
    if (date == null) return null;

    final debit = _find(h, ['debit', 'dr', 'withdrawal', 'withdrawals'], ['debit', 'withdrawal']);
    final credit = _find(h, ['credit', 'cr', 'deposit', 'deposits'], ['credit', 'deposit']);
    final amount = _find(h, ['amount', 'amt', 'transaction amount'], ['amount']);
    final hasMoney = debit != null || credit != null || amount != null;
    if (!hasMoney) return null;

    int? exclude(int? index) => index == date ? null : index;
    return _Columns(
      date: date,
      debit: debit,
      credit: credit,
      amount: debit == null && credit == null ? exclude(amount) : null,
      description: _find(h, ['description', 'narration', 'details', 'particulars', 'remarks', 'transaction details', 'note', 'activity'],
          ['narration', 'description', 'particular', 'detail', 'remark', 'note']),
      type: _find(h, ['type', 'dr/cr', 'cr/dr', 'transaction type'], ['dr/cr', 'cr/dr']),
      reference: _find(h, ['utr', 'ref no', 'reference', 'reference no', 'upi ref', 'upi reference', 'transaction id', 'txn id', 'rrn', 'upi ref no.'],
          ['utr', 'ref', 'rrn', 'txn id', 'transaction id']),
      category: _find(h, ['category'], []),
    );
  }
}
