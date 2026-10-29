import '../../models/expense.dart';
import 'csv_statement_parser.dart';
import 'imported_transaction.dart';
import 'pdf_lines.dart';

/// Reads bank account statement PDFs that print a table with Date, Narration,
/// Withdrawal, Deposit and Balance columns (HDFC Bank's layout). Columns are
/// found from the header row's word positions, and a transaction runs from one
/// date to the next because narrations wrap over several lines.
class BankPdfParser {
  static final _stop = RegExp(
    r'^(?:Cr Count|Dr Count|Debits|Credits|Opening Balance|Closing Balance|STATEMENT SUMMARY\s*:?-?)$'
    r'|^(?:\*\*END|Generation Date|Page\s+\d+\s+of|\*Closing Balance)',
    caseSensitive: false,
  );
  static final _upi = RegExp(r'^UPI-(.+?)-(\S+?@\w+)-([A-Z]{4}0[A-Z0-9]{6})-(\d{6,})-');
  static final _atm = RegExp(r'^(?:NWD|ATW|EAW)-[^-]+-[^-]+-(.+)$');
  static final _pos = RegExp(r'^POS\s+\S+\s+(.+)$');
  static final _neft = RegExp(r'^NEFT\s+(DR|CR)-[A-Z]{4}0[A-Z0-9]{6}-(.+?)-', caseSensitive: false);
  static final _twelveDigits = RegExp(r'^\d{12}$');

  static bool looksLikeBank(List<PdfLine> lines) => lines.any((l) => _header(l) != null);

  static ParsedStatement parse(List<PdfLine> lines) {
    final items = <ImportedTransaction>[];
    List<_Column>? columns;
    _Pending? pending;

    void flush() {
      final done = pending?.toTransaction();
      pending = null;
      if (done != null) items.add(done);
    }

    for (final line in lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;

      final header = _header(line);
      if (header != null) {
        flush();
        columns = header;
        continue;
      }
      if (_stop.hasMatch(text)) {
        // Page footer or summary: the transaction ends here. The columns stay, because
        // later pages continue the same table without repeating the header row.
        flush();
        continue;
      }
      final cols = columns;
      if (cols == null) continue;

      DateTime? date;
      final narration = StringBuffer();
      var ref = '';
      double? withdrawal;
      double? deposit;
      for (final word in line.words) {
        final kind = _kindAt(cols, word.x);
        final value = word.text.trim();
        if (kind == null) continue;
        switch (kind) {
          case _Kind.date:
            date ??= value.isEmpty ? null : CsvStatementParser.parseDate(value);
          case _Kind.narration:
            narration.write(word.text);
          case _Kind.ref:
            ref += value;
          case _Kind.withdrawal:
            if (value.isNotEmpty) withdrawal = CsvStatementParser.parseNumber(value);
          case _Kind.deposit:
            if (value.isNotEmpty) deposit = CsvStatementParser.parseNumber(value);
          case _Kind.valueDate:
          case _Kind.balance:
            break;
        }
      }

      if (date != null) {
        flush();
        pending = _Pending(date);
      }
      final current = pending;
      if (current == null) continue;
      // Wrapped narration lines are cut at a fixed width, so they join without a space.
      current.narration.write(narration.toString().trim());
      if (ref.isNotEmpty) current.ref = ref;
      if (withdrawal != null && withdrawal > 0) current.withdrawal = withdrawal;
      if (deposit != null && deposit > 0) current.deposit = deposit;
    }
    flush();

    final totals = _summary(lines);
    return ParsedStatement(
      sourceLabel: 'Bank statement (PDF)',
      items: items,
      statedExpenseTotal: totals.$1,
      statedIncomeTotal: totals.$2,
    );
  }

  /// The "Debits" and "Credits" totals printed in the statement summary, if any.
  static (double?, double?) _summary(List<PdfLine> lines) {
    double? debits;
    double? credits;
    for (var i = 0; i + 1 < lines.length; i++) {
      final label = lines[i].text.trim().toLowerCase();
      if (label != 'debits' && label != 'credits') continue;
      final value = CsvStatementParser.parseNumber(lines[i + 1].text);
      if (value == null) continue;
      if (label == 'debits') {
        debits = value;
      } else {
        credits = value;
      }
    }
    return (debits, credits);
  }

  static List<_Column>? _header(PdfLine line) {
    final words = line.words.where((w) => w.text.trim().isNotEmpty).toList();
    _Column? firstOf(_Kind kind, List<String> names) {
      _Column? best;
      for (final w in words) {
        final name = w.text.toLowerCase().replaceAll('*', '');
        if (names.contains(name) && (best == null || w.x < best.x)) best = _Column(kind, w.x);
      }
      return best;
    }

    final date = firstOf(_Kind.date, ['date']);
    final narration = firstOf(_Kind.narration, ['narration']);
    final withdrawal = firstOf(_Kind.withdrawal, ['withdrawal', 'withdrawals', 'debit', 'debits']);
    final deposit = firstOf(_Kind.deposit, ['deposit', 'deposits', 'credit', 'credits']);
    if (date == null || narration == null || withdrawal == null || deposit == null) return null;

    final columns = [
      date,
      narration,
      withdrawal,
      deposit,
      firstOf(_Kind.ref, ['chq.', 'chq', 'cheque', 'ref']),
      firstOf(_Kind.valueDate, ['value']),
      firstOf(_Kind.balance, ['closing', 'balance']),
    ].whereType<_Column>().toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    return columns;
  }

  static _Kind? _kindAt(List<_Column> columns, double x) {
    _Kind? found;
    for (final c in columns) {
      if (x >= c.x - 6) found = c.kind;
    }
    return found;
  }
}

enum _Kind { date, narration, ref, valueDate, withdrawal, deposit, balance }

class _Column {
  final _Kind kind;
  final double x;

  const _Column(this.kind, this.x);
}

class _Pending {
  final DateTime date;
  final StringBuffer narration = StringBuffer();
  String ref = '';
  double? withdrawal;
  double? deposit;

  _Pending(this.date);

  ImportedTransaction? toTransaction() {
    final isExpense = withdrawal != null;
    final amount = withdrawal ?? deposit;
    if (amount == null) return null;

    final raw = narration.toString().trim();
    var description = raw;
    var method = 'Online';

    final upi = BankPdfParser._upi.firstMatch(raw);
    final atm = BankPdfParser._atm.firstMatch(raw);
    final pos = BankPdfParser._pos.firstMatch(raw);
    final neft = BankPdfParser._neft.firstMatch(raw);
    if (upi != null) {
      description = upi.group(1)!.trim();
      if (ref.isEmpty) ref = upi.group(4)!;
    } else if (atm != null) {
      description = 'ATM cash withdrawal ${atm.group(1)!.trim()}';
      method = 'Cash';
    } else if (pos != null) {
      description = pos.group(1)!.trim();
      method = 'Card';
    } else if (neft != null) {
      final paid = neft.group(1)!.toUpperCase() == 'DR';
      description = 'NEFT ${paid ? 'to' : 'from'} ${neft.group(2)!.trim()}';
    }

    return ImportedTransaction(
      date: date,
      description: description,
      amount: amount,
      type: isExpense ? TransactionType.expense : TransactionType.income,
      upiRef: BankPdfParser._twelveDigits.hasMatch(ref) ? ref : null,
      paymentMethod: method,
    );
  }
}
