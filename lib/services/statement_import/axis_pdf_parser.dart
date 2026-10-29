import '../../models/expense.dart';
import 'csv_statement_parser.dart';
import 'imported_transaction.dart';
import 'pdf_lines.dart';

/// Reads Axis Bank savings account statement PDFs: a "Txn Date, Transaction,
/// Withdrawals, Deposits, Balance" table. The amounts are right aligned under
/// their headings, so each amount goes to the heading it is closest to, and a
/// transaction runs from one date to the next because narrations wrap.
class AxisPdfParser {
  static final _stop = RegExp(r'^(?:Closing Balance|Legends used|Page\s+\d+\s+of)', caseSensitive: false);
  static final _refToken = RegExp(r'\s*Ref#\S+');
  static final _upi = RegExp(r'^UPI/(?:P2M|P2A|P2P)/(\d{9,})/([^/]+)', caseSensitive: false);
  static final _twelveDigits = RegExp(r'(?<!\d)(\d{12})(?!\d)');

  static bool looksLikeAxis(List<PdfLine> lines) => lines.any((l) => _header(l) != null);

  static ParsedStatement parse(List<PdfLine> lines) {
    final items = <ImportedTransaction>[];
    _Header? header;
    _Pending? pending;
    double? opening;
    double? closing;

    void flush() {
      final done = pending?.toTransaction();
      pending = null;
      if (done != null) items.add(done);
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
      if (header == null) continue;

      if (text.toLowerCase() == 'opening balance' && i + 1 < lines.length) {
        opening ??= CsvStatementParser.parseNumber(lines[i + 1].text);
        continue;
      }
      if (_stop.hasMatch(text)) {
        flush();
        if (text.toLowerCase().startsWith('closing balance')) {
          closing ??= CsvStatementParser.parseNumber(text.substring('closing balance'.length));
        }
        // The table ends at the closing balance; a later header starts a new one.
        header = null;
        continue;
      }

      final words = line.words.where((w) => w.text.trim().isNotEmpty).toList();
      if (words.isEmpty) continue;

      final first = words.first;
      final date = first.x < header.narrationX ? CsvStatementParser.parseDate(first.text.trim()) : null;
      if (date != null) {
        flush();
        pending = _Pending(date);
      }
      final current = pending;
      if (current == null) continue;

      final narration = <String>[];
      for (final word in line.words) {
        final value = word.text.trim();
        if (identical(word, first) && date != null) continue;
        if (value.isEmpty) {
          if (word.x < header.firstAmountX - 6) narration.add(' ');
          continue;
        }
        if (word.x >= header.firstAmountX - 6) {
          final number = CsvStatementParser.parseNumber(value);
          if (number == null || number <= 0) continue;
          switch (header.amountColumnAt(word.center)) {
            case _Amount.withdrawal:
              current.withdrawal = number;
            case _Amount.deposit:
              current.deposit = number;
            case _Amount.balance:
              break;
          }
        } else {
          narration.add(word.text);
        }
      }
      final part = narration.join().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (part.isNotEmpty) current.narration.add(part);
    }
    flush();

    return ParsedStatement(
      sourceLabel: 'Axis Bank statement (PDF)',
      items: items,
      statedOpening: opening,
      statedClosing: closing,
    );
  }

  static _Header? _header(PdfLine line) {
    final words = line.words.where((w) => w.text.trim().isNotEmpty).toList();
    PdfWord? find(List<String> names) {
      for (final w in words) {
        if (names.contains(w.text.trim().toLowerCase())) return w;
      }
      return null;
    }

    final withdrawals = find(['withdrawals', 'withdrawal', 'debit']);
    final deposits = find(['deposits', 'deposit', 'credit']);
    final balance = find(['balance']);
    final transaction = find(['transaction', 'particulars', 'narration']);
    final txn = find(['txn', 'tran', 'date']);
    if (withdrawals == null || deposits == null || balance == null || transaction == null || txn == null) return null;
    // Axis prints "Withdrawals" and "Deposits"; a header with Debit/Credit is some other bank's layout.
    if (withdrawals.text.trim().toLowerCase() != 'withdrawals' || deposits.text.trim().toLowerCase() != 'deposits') return null;
    return _Header(
      narrationX: transaction.x,
      withdrawals: withdrawals,
      deposits: deposits,
      balance: balance,
    );
  }
}

enum _Amount { withdrawal, deposit, balance }

class _Header {
  final double narrationX;
  final PdfWord withdrawals;
  final PdfWord deposits;
  final PdfWord balance;

  const _Header({required this.narrationX, required this.withdrawals, required this.deposits, required this.balance});

  double get firstAmountX => withdrawals.x;

  /// The amount heading whose centre is closest to the given centre.
  _Amount amountColumnAt(double center) {
    final distances = {
      _Amount.withdrawal: (center - withdrawals.center).abs(),
      _Amount.deposit: (center - deposits.center).abs(),
      _Amount.balance: (center - balance.center).abs(),
    };
    return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }
}

class _Pending {
  final DateTime date;
  final List<String> narration = [];
  double? withdrawal;
  double? deposit;

  _Pending(this.date);

  ImportedTransaction? toTransaction() {
    final amount = withdrawal ?? deposit;
    if (amount == null) return null;

    final raw = narration.join(' ').trim();
    var description = raw.replaceAll(AxisPdfParser._refToken, '').trim();
    String? ref;
    final upi = AxisPdfParser._upi.firstMatch(raw);
    if (upi != null) {
      ref = upi.group(1);
      description = upi.group(2)!.trim();
    } else {
      ref = AxisPdfParser._twelveDigits.firstMatch(raw)?.group(1);
    }

    return ImportedTransaction(
      date: date,
      description: description,
      amount: amount,
      type: withdrawal != null ? TransactionType.expense : TransactionType.income,
      upiRef: ref != null && ref.length == 12 ? ref : null,
      paymentMethod: raw.toUpperCase().contains('ATM') ? 'Cash' : 'Online',
    );
  }
}
