import '../../models/expense.dart';
import 'csv_statement_parser.dart';
import 'imported_transaction.dart';
import 'pdf_lines.dart';

/// Best-effort reader for other banks' savings account statement PDFs that print
/// a table with a Date, a description, Debit/Withdrawal and Credit/Deposit amounts
/// and a Balance. It finds the headings by name, hands each amount to the nearest
/// heading (so left or right aligned columns both work) and checks the result
/// against the running balances. It is only used when no bank-specific reader fits.
class TablePdfParser {
  static final _stop = RegExp(
    r'^(?:Closing Balance|Opening Balance|Legends|Statement Summary|End of Statement|\*\*END|Page\s+\d+\s+of|Total\b|Grand Total)',
    caseSensitive: false,
  );
  static final _amount = RegExp(r'^\(?[\d,]*\d\.\d{2}\)?(?:\s?(?:Cr|Dr))?$', caseSensitive: false);
  static final _upiSlash = RegExp(r'UPI/(?:[A-Z0-9]{2,3}/)?(\d{12})/([^/]+)', caseSensitive: false);
  static final _dateOrTime = RegExp(r'^(?:\d{1,2}[-/. ][A-Za-z0-9]{1,3}[-/. ]\d{2,4}|\d{1,2}:\d{2}(?::\d{2})?)$');
  static final _twelveDigits = RegExp(r'(?<!\d)(\d{12})(?!\d)');

  static bool looksLikeTable(List<PdfLine> lines) => lines.any((l) => _header(l) != null);

  static ParsedStatement parse(List<PdfLine> lines) {
    final items = <ImportedTransaction>[];
    final balances = <double?>[];
    _Header? header;
    _Pending? pending;
    double? openingFromLine;

    void flush() {
      final done = pending;
      pending = null;
      if (done == null) return;
      final txn = done.toTransaction();
      if (txn == null) return;
      items.add(txn);
      balances.add(done.balance);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final text = line.text.trim();
      if (text.isEmpty) continue;

      final found = _header(line);
      if (found != null) {
        flush();
        header = found;
        continue;
      }
      final h = header;
      if (h == null) continue;

      if (_stop.hasMatch(text)) {
        flush();
        if (text.toLowerCase().startsWith('opening balance')) {
          openingFromLine ??= _numberIn(text.substring('opening balance'.length)) ??
              (i + 1 < lines.length ? _numberIn(lines[i + 1].text) : null);
        }
        continue;
      }

      final words = line.words.where((w) => w.text.trim().isNotEmpty).toList();
      if (words.isEmpty) continue;

      // A row starts with a date (one word like 05/10/2026, or three like 5 Oct 2026),
      // optionally after a serial number.
      final dateWords = <PdfWord>[];
      DateTime? date;
      for (final start in [0, 1]) {
        if (start == 1 && !(words.length > 1 && RegExp(r'^\d{1,4}$').hasMatch(words[0].text.trim()) && words[0].x < h.descriptionX)) break;
        final found = _dateAt(words, start);
        if (found != null && words[start].x < h.firstAmountX - 12) {
          date = found.$1;
          dateWords.addAll(start == 1 ? [words[0]] : const []);
          dateWords.addAll(words.sublist(start, start + found.$2));
          break;
        }
      }
      if (date != null) {
        flush();
        pending = _Pending(date);
      }
      final current = pending;
      if (current == null) continue;

      // Dates written as three words (such as a value date) are not part of the description.
      final skipWords = <PdfWord>[...dateWords];
      for (var i = 0; i < words.length; i++) {
        final found = _dateAt(words, i);
        if (found != null && found.$2 == 3) skipWords.addAll(words.sublist(i, i + 3));
      }
      final narration = StringBuffer();
      for (final word in line.words) {
        final value = word.text.trim();
        if (skipWords.any((d) => identical(d, word))) continue;
        if (value.isEmpty) {
          if (word.x < h.narrationEndX) narration.write(' ');
          continue;
        }
        if (word.x >= h.firstAmountX - 12 && _amount.hasMatch(value)) {
          final number = CsvStatementParser.parseNumber(value.replaceAll(RegExp(r'[A-Za-z\s]'), ''));
          if (number == null) continue;
          switch (h.columnAt(word.center)) {
            case _Column.debit:
              if (number > 0) current.debit = number;
            case _Column.credit:
              if (number > 0) current.credit = number;
            case _Column.balance:
              current.balance = number.abs();
          }
        } else if (word.x < h.narrationEndX && !_dateOrTime.hasMatch(value)) {
          narration.write(word.text);
        }
      }
      final part = narration.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (part.isNotEmpty) current.narration.add(part);
    }
    flush();

    // Running balances give an opening and closing balance to check the amounts against.
    double? opening;
    double? closing;
    if (items.isNotEmpty && balances.every((b) => b != null)) {
      final firstBalance = balances.first!;
      opening = openingFromLine ?? (items.first.isIncome ? firstBalance - items.first.amount : firstBalance + items.first.amount);
      closing = balances.last;
    }
    return ParsedStatement(
      sourceLabel: 'Bank statement (PDF)',
      items: items,
      statedOpening: opening,
      statedClosing: closing,
    );
  }

  /// A date starting at words[start]: one word, or three such as "5 Oct 2026".
  static (DateTime, int)? _dateAt(List<PdfWord> words, int start) {
    final single = CsvStatementParser.parseDate(words[start].text.trim());
    if (single != null) return (single, 1);
    if (start + 2 < words.length) {
      final joined = '${words[start].text.trim()} ${words[start + 1].text.trim()} ${words[start + 2].text.trim()}';
      if (RegExp(r'^\d{1,2} [A-Za-z]{3,9},? \d{2,4}$').hasMatch(joined)) {
        final date = CsvStatementParser.parseDate(joined);
        if (date != null) return (date, 3);
      }
    }
    return null;
  }

  static double? _numberIn(String text) {
    final m = RegExp(r'[\d,]*\d\.\d{2}').firstMatch(text);
    return m == null ? null : CsvStatementParser.parseNumber(m.group(0)!);
  }

  static _Header? _header(PdfLine line) {
    final words = line.words.where((w) => w.text.trim().isNotEmpty).toList();
    PdfWord? find(List<String> names) {
      PdfWord? best;
      for (final w in words) {
        final name = w.text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        if (names.contains(name) && (best == null || w.x < best.x)) best = w;
      }
      return best;
    }

    final date = find(['date', 'txn', 'tran', 'trans']);
    final debit = find(['withdrawal', 'withdrawals', 'withdraws', 'withdrawn', 'debit', 'debits', 'dr']);
    final credit = find(['deposit', 'deposits', 'credit', 'credits', 'cr']);
    final balance = find(['balance', 'bal']);
    if (date == null || debit == null || credit == null || balance == null) return null;
    const descriptionNames = ['description', 'particulars', 'narration', 'details', 'remarks', 'transaction'];
    final description = find(descriptionNames);
    // A heading between the description and the first amount (such as Branch Code) is
    // another column, so the description stops before it.
    final amountStart = [debit.x, credit.x, balance.x].reduce((a, b) => a < b ? a : b);
    double? descriptionEnd;
    if (description != null) {
      for (final w in words) {
        final name = w.text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        if (w.x > description.x + 20 && w.x < amountStart - 12 && !descriptionNames.contains(name)) {
          if (descriptionEnd == null || w.x < descriptionEnd) descriptionEnd = w.x;
        }
      }
    }
    return _Header(
      descriptionX: description?.x ?? date.x + 40,
      narrationEndX: descriptionEnd != null ? descriptionEnd - 4 : amountStart - 12,
      debit: debit,
      credit: credit,
      balance: balance,
    );
  }
}

enum _Column { debit, credit, balance }

class _Header {
  final double descriptionX;
  final double narrationEndX;
  final PdfWord debit;
  final PdfWord credit;
  final PdfWord balance;

  const _Header({required this.descriptionX, required this.narrationEndX, required this.debit, required this.credit, required this.balance});

  double get firstAmountX {
    final xs = [debit.x, credit.x, balance.x]..sort();
    return xs.first;
  }

  _Column columnAt(double center) {
    final distances = {
      _Column.debit: (center - debit.center).abs(),
      _Column.credit: (center - credit.center).abs(),
      _Column.balance: (center - balance.center).abs(),
    };
    return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }
}

class _Pending {
  final DateTime date;
  final List<String> narration = [];
  double? debit;
  double? credit;
  double? balance;

  _Pending(this.date);

  ImportedTransaction? toTransaction() {
    final amount = debit ?? credit;
    if (amount == null) return null;

    final raw = narration.join(' ').trim();
    var description = raw;
    String? ref;
    final upi = TablePdfParser._upiSlash.firstMatch(raw);
    if (upi != null) {
      ref = upi.group(1);
      description = upi.group(2)!.trim();
    } else {
      ref = TablePdfParser._twelveDigits.firstMatch(raw)?.group(1);
    }

    return ImportedTransaction(
      date: date,
      description: description,
      amount: amount,
      type: debit != null ? TransactionType.expense : TransactionType.income,
      upiRef: ref,
      paymentMethod: raw.toUpperCase().contains('ATM') ? 'Cash' : 'Online',
    );
  }
}
