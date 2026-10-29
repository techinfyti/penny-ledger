import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:penny_ledger/models/expense.dart';
import 'package:penny_ledger/services/statement_import/axis_pdf_parser.dart';
import 'package:penny_ledger/services/statement_import/bank_pdf_parser.dart';
import 'package:penny_ledger/services/statement_import/category_suggester.dart';
import 'package:penny_ledger/services/statement_import/csv_statement_parser.dart';
import 'package:penny_ledger/services/statement_import/imported_transaction.dart';
import 'package:penny_ledger/services/statement_import/pdf_lines.dart';
import 'package:penny_ledger/services/statement_import/statement_reader.dart';
import 'package:penny_ledger/services/statement_import/table_pdf_parser.dart';

void main() {
  group('Google Pay PDF', () {
    final file = File('samples/gpay_statement_20260901_20260930.pdf');

    test('reads every transaction and matches the statement totals', () async {
      final parsed = await StatementReader.read(fileName: 'gpay.pdf', bytes: file.readAsBytesSync());

      expect(parsed.items.length, 82);
      expect(parsed.items.where((t) => !t.isIncome).length, 66);
      expect(parsed.items.where((t) => t.isIncome).length, 16);
      expect(parsed.statedExpenseTotal, 25799);
      expect(parsed.statedIncomeTotal, 10008.01);
      expect(parsed.expenseTotal, closeTo(25799, 0.01));
      expect(parsed.incomeTotal, closeTo(10008.01, 0.01));
      expect(parsed.totalsMatch, isTrue);
      expect(parsed.items.map((t) => t.upiRef).toSet().length, 82);
      expect(parsed.items.every((t) => t.description.isNotEmpty), isTrue);
      expect(parsed.items.first.date.month, 9);
      expect(parsed.items.first.date.year, 2026);
    }, skip: file.existsSync() ? false : 'sample statement not present');
  });

  group('Bank account statement PDF (HDFC layout)', () {
    PdfLine ln(List<(String, double)> words) =>
        PdfLine(words.map((w) => w.$1).join(' '), [for (final w in words) PdfWord(w.$1, w.$2)]);

    final header = ln([
      ('Date', 11), ('Narration', 77), ('Chq.', 291), ('/', 309), ('Ref', 313), ('No.', 326),
      ('Value', 411), ('Date', 432), ('Withdrawal', 508), ('Amount', 548), ('Deposit', 594), ('Amount', 621),
      ('Closing', 688), ('Balance*', 715),
    ]);

    test('joins wrapped narrations, keeps columns on later pages and checks the printed totals', () {
      final lines = [
        ln([('Mr. A Customer', 23)]),
        header,
        ln([('29/09/2026', 11)]),
        ln([('UPI-MAHESWARAN R-MAHESWARAN80@OKSBI-SBIN', 77)]),
        ln([('0003351-130396643341-UPI', 77)]),
        ln([('130396643341', 291), ('29/09/2026', 411), ('50.00', 508), ('0.00', 594), ('343.17', 688)]),
        ln([('30/09/2026', 11), ('011968094121', 77), ('011968094121', 291), ('30/09/2026', 411), ('0.00', 508), ('1,77,582.00', 594), ('1,77,777.17', 688)]),
        ln([('*Closing Balance includes funds enmarked for hold', 257)]),
        ln([('Page 1 of 2', 710)]),
        // Page 2 has no header row, only the customer block and then more rows.
        ln([('Mr. A Customer', 23)]),
        ln([('Statement From : 29/09/26   TO : 28/10/26', 20), ('29/09/26', 101)]),
        ln([('A/C Open Date', 364)]),
        ln([('01/10/2026', 11)]),
        ln([('NWD-541919XXXXXX7721-C0162303-PATTUKOTTA', 77)]),
        ln([('I', 77)]),
        ln([('627419878442', 291), ('01/10/2026', 411), ('7,000.00', 508), ('0.00', 594), ('1,71,035.17', 688)]),
        ln([('03/10/2026', 11)]),
        ln([('NEFT DR-UTIB0000486-VIJAYAGANESH-NETBANK, MUM-HDFCH01301440488', 77)]),
        ln([('0000000000001', 291), ('03/10/2026', 411), ('10.00', 508), ('0.00', 594), ('1,71,025.17', 688)]),
        ln([('Cr Count', 305)]),
        ln([('1', 333)]),
        ln([('Debits', 436)]),
        ln([('7,060.00', 417)]),
        ln([('Credits', 574)]),
        ln([('177,582.00', 560)]),
        ln([('Opening Balance', 77)]),
        ln([('393.17', 77)]),
      ];

      expect(BankPdfParser.looksLikeBank(lines), isTrue);
      final parsed = BankPdfParser.parse(lines);

      expect(parsed.items.length, 4);
      expect(parsed.items[0].description, 'MAHESWARAN R');
      expect(parsed.items[0].amount, 50);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].upiRef, '130396643341');
      expect(parsed.items[0].date, DateTime(2026, 9, 29));
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 177582);
      expect(parsed.items[2].description, 'ATM cash withdrawal PATTUKOTTAI');
      expect(parsed.items[2].paymentMethod, 'Cash');
      expect(parsed.items[2].amount, 7000);
      expect(parsed.items[3].description, 'NEFT to VIJAYAGANESH');
      expect(parsed.items[3].isIncome, isFalse);
      expect(parsed.statedExpenseTotal, 7060);
      expect(parsed.statedIncomeTotal, 177582);
      expect(parsed.totalsMatch, isTrue);
    });

    test('a page without the transaction table is not a bank statement', () {
      expect(BankPdfParser.looksLikeBank([ln([('Annual report', 20)])]), isFalse);
    });
  });

  group('Axis Bank statement PDF', () {
    PdfWord w(String text, double x, [double width = 0]) => PdfWord(text, x, width);
    PdfLine ln(String text, List<PdfWord> words) => PdfLine(text, words);

    final header = ln('Txn Date Transaction Withdrawals Deposits Balance', [
      w('Txn', 30, 15), w('Date', 50, 20), w('Transaction', 149, 50), w('Withdrawals', 281, 55), w('Deposits', 356, 40), w('Balance', 430, 35),
    ]);

    test('puts right aligned amounts under their headings and checks the balances', () {
      final lines = [
        ln('Account Statement', [w('Account', 30, 40)]),
        header,
        ln('Opening Balance', [w('Opening', 81, 35), w(' ', 117), w('Balance', 125, 35)]),
        ln('21,777.90', [w('21,777.90', 436, 40)]),
        ln('05-09-2026 CreditCard Payment XX 9388', [
          w('05-09-2026', 24, 50), w('CreditCard', 81, 45), w(' ', 128), w('Payment', 135, 35), w(' ', 171), w('XX', 175, 12), w(' ', 189), w('9388', 192, 20),
        ]),
        ln('Ref#S5LFUJHY5UD5QU', [w('Ref#S5LFUJHY5UD5QU', 81, 90)]),
        ln('8,847.82', [w('8,847.82', 299, 36)]),
        ln('10-09-2026 UPI/P2M/412345678901/', [w('10-09-2026', 24, 50), w('UPI/P2M/412345678901/', 81, 100)]),
        ln('Swiggy', [w('Swiggy', 81, 30)]),
        ln('250.00', [w('250.00', 372, 30)]),
        ln('13,180.08', [w('13,180.08', 436, 40)]),
        ln('Closing Balance 13,180.08', [w('Closing', 81, 35), w(' ', 118), w('Balance', 121, 35), w('13,180.08', 438, 40)]),
        ln('Legends used in the Statement', [w('Legends', 230, 38)]),
        ln('PUR Purchase using the debit card', [w('PUR', 204, 15), w('Purchase', 221, 32)]),
      ];

      expect(AxisPdfParser.looksLikeAxis(lines), isTrue);
      final parsed = AxisPdfParser.parse(lines);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].description, 'CreditCard Payment XX 9388');
      expect(parsed.items[0].amount, 8847.82);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].date, DateTime(2026, 9, 5));
      expect(parsed.items[1].description, 'Swiggy');
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 250);
      expect(parsed.items[1].upiRef, '412345678901');
      expect(parsed.statedOpening, 21777.90);
      expect(parsed.statedClosing, 13180.08);
      expect(parsed.checksBalances, isTrue);
      expect(parsed.totalsMatch, isTrue);
    });

    test('flags a statement whose transactions do not add up to the balances', () {
      final lines = [
        header,
        ln('Opening Balance', [w('Opening', 81, 35), w(' ', 117), w('Balance', 125, 35)]),
        ln('1,000.00', [w('1,000.00', 436, 40)]),
        ln('05-09-2026 Cash', [w('05-09-2026', 24, 50), w('Cash', 81, 25)]),
        ln('100.00', [w('100.00', 299, 30)]),
        ln('Closing Balance 500.00', [w('Closing', 81, 35), w(' ', 118), w('Balance', 121, 35), w('500.00', 438, 30)]),
      ];
      expect(AxisPdfParser.parse(lines).totalsMatch, isFalse);
    });

    test('an HDFC style header is not mistaken for Axis', () {
      final hdfc = ln('Date Narration Withdrawal Amount Deposit Amount Closing Balance', [
        w('Date', 11), w('Narration', 77), w('Withdrawal', 508), w('Amount', 548), w('Deposit', 594), w('Amount', 621), w('Closing', 688), w('Balance*', 715),
      ]);
      expect(AxisPdfParser.looksLikeAxis([hdfc]), isFalse);
    });
  });

  group('Other banks\' PDF tables (best effort)', () {
    PdfWord w(String text, double x, [double width = 0]) => PdfWord(text, x, width);
    PdfLine ln(String text, List<PdfWord> words) => PdfLine(text, words);

    test('ICICI style: Deposits before Withdrawals, a Mode column and running balances', () {
      final lines = [
        ln('Statement of Transactions in Savings Account', [w('Statement', 30, 50)]),
        ln('DATE MODE** PARTICULARS DEPOSITS WITHDRAWALS BALANCE', [
          w('DATE', 30, 25), w('MODE**', 90, 35), w('PARTICULARS', 160, 60), w('DEPOSITS', 330, 45), w('WITHDRAWALS', 400, 62), w('BALANCE', 490, 38),
        ]),
        ln('03-02-2023 UPI UPI/P2M/412345678901/Swiggy', [
          w('03-02-2023', 30, 52), w('UPI', 90, 18), w(' ', 109), w('UPI/P2M/412345678901/Swiggy', 160, 120),
        ]),
        ln('349.00', [w('349.00', 425, 32)]),
        ln('9,651.00', [w('9,651.00', 490, 38)]),
        ln('05-02-2023 NEFT SALARY ACME LTD', [
          w('05-02-2023', 30, 52), w('NEFT', 90, 24), w(' ', 115), w('SALARY', 160, 36), w(' ', 197), w('ACME', 199, 25),
        ]),
        ln('wrapped line', [w('LTD', 160, 20)]),
        ln('50,000.00', [w('50,000.00', 330, 45)]),
        ln('59,651.00', [w('59,651.00', 490, 38)]),
        ln('Page 1 of 1', [w('Page', 300, 20)]),
      ];

      expect(TablePdfParser.looksLikeTable(lines), isTrue);
      final parsed = TablePdfParser.parse(lines);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].description, 'Swiggy');
      expect(parsed.items[0].upiRef, '412345678901');
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].amount, 349);
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 50000);
      expect(parsed.items[1].description, contains('SALARY ACME'));
      expect(parsed.items[1].date, DateTime(2023, 2, 5));
      expect(parsed.checksBalances, isTrue);
      expect(parsed.totalsMatch, isTrue);
    });

    test('Canara style: value date, cheque number and branch code columns are not part of the description', () {
      final lines = [
        ln('Txn Date Value Date Cheque No. Description Branch Code Debit Credit Balance', [
          w('Txn', 25, 15), w('Date', 43, 20), w('Value', 85, 25), w('Date', 112, 20), w('Cheque', 145, 30), w('No.', 177, 15),
          w('Description', 205, 52), w('Branch', 340, 30), w('Code', 372, 20), w('Debit', 420, 25), w('Credit', 470, 28), w('Balance', 525, 35),
        ]),
        ln('05-10-2026 14:22:10 05-10-2026 UPI/DR/412345678901/Hotel Saravana 33', [
          w('05-10-2026', 25, 52), w(' ', 78), w('14:22:10', 40, 0), w('05-10-2026', 85, 52), w('UPI/DR/412345678901/Hotel Saravana', 205, 120), w('33', 345, 10),
        ]),
        ln('120.00', [w('120.00', 418, 30)]),
        ln('4,880.00', [w('4,880.00', 523, 38)]),
        ln('06-10-2026 06-10-2026 INTEREST', [w('06-10-2026', 25, 52), w('06-10-2026', 85, 52), w('INTEREST', 205, 40), w('33', 345, 10)]),
        ln('15.00', [w('15.00', 470, 28)]),
        ln('4,895.00', [w('4,895.00', 523, 38)]),
        ln('Closing Balance 4,895.00', [w('Closing', 205, 35), w('Balance', 245, 35), w('4,895.00', 523, 38)]),
      ];

      expect(TablePdfParser.looksLikeTable(lines), isTrue);
      final parsed = TablePdfParser.parse(lines);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].description, 'Hotel Saravana');
      expect(parsed.items[0].amount, 120);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[1].description, 'INTEREST');
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 15);
      expect(parsed.totalsMatch, isTrue);
    });

    test('State Bank style: dates written as 5 Oct 2026 and a Ref No./Cheque No. column', () {
      final lines = [
        ln('Txn Date Value Date Description Ref No./Cheque No. Debit Credit Balance', [
          w('Txn', 25, 15), w('Date', 43, 20), w('Value', 90, 25), w('Date', 117, 20), w('Description', 160, 52),
          w('Ref', 300, 12), w('No./Cheque', 315, 48), w('No.', 366, 15), w('Debit', 420, 25), w('Credit', 475, 28), w('Balance', 530, 35),
        ]),
        ln('5 Oct 2026 5 Oct 2026 TO TRANSFER-UPI/DR/412345678901/RAVI KUMAR/SBIN/', [
          w('5', 25, 5), w(' ', 31), w('Oct', 33, 15), w(' ', 49), w('2026', 51, 22), w('5', 90, 5), w(' ', 96), w('Oct', 98, 15), w(' ', 114), w('2026', 116, 22),
          w('TO TRANSFER-UPI/DR/412345678901/RAVI KUMAR/SBIN/', 160, 130),
        ]),
        ln('500.00', [w('500.00', 418, 30)]),
        ln('9,500.00', [w('9,500.00', 528, 38)]),
        ln('7 Oct 2026 7 Oct 2026 BY TRANSFER-NEFT*ACME*SALARY', [
          w('7', 25, 5), w('Oct', 33, 15), w('2026', 51, 22), w('7', 90, 5), w('Oct', 98, 15), w('2026', 116, 22), w('BY TRANSFER-NEFT*ACME*SALARY', 160, 120),
        ]),
        ln('25,000.00', [w('25,000.00', 473, 36)]),
        ln('34,500.00', [w('34,500.00', 528, 38)]),
      ];

      final parsed = TablePdfParser.parse(lines);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].date, DateTime(2026, 10, 5));
      expect(parsed.items[0].description, 'RAVI KUMAR');
      expect(parsed.items[0].upiRef, '412345678901');
      expect(parsed.items[0].amount, 500);
      expect(parsed.items[1].date, DateTime(2026, 10, 7));
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].description, 'BY TRANSFER-NEFT*ACME*SALARY');
      expect(parsed.totalsMatch, isTrue);
    });

    test('Indian Bank style: Post Date, Details and Chq.No. columns', () {
      final lines = [
        ln('Post Date Value Date Details Chq.No. Debit Credit Balance', [
          w('Post', 25, 20), w('Date', 47, 20), w('Value', 90, 25), w('Date', 117, 20), w('Details', 160, 35),
          w('Chq.No.', 330, 35), w('Debit', 410, 25), w('Credit', 465, 28), w('Balance', 520, 35),
        ]),
        ln('05/10/2026 05/10/2026 UPI/412345678901/Milk Vendor', [w('05/10/2026', 25, 52), w('05/10/2026', 90, 52), w('UPI/412345678901/Milk Vendor', 160, 120)]),
        ln('60.00', [w('60.00', 408, 28)]),
        ln('940.00', [w('940.00', 518, 30)]),
      ];

      final parsed = TablePdfParser.parse(lines);

      expect(parsed.items.length, 1);
      expect(parsed.items[0].amount, 60);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].date, DateTime(2026, 10, 5));
      expect(parsed.items[0].upiRef, '412345678901');
      expect(parsed.items[0].description, 'Milk Vendor');
      expect(parsed.totalsMatch, isTrue);
    });

    test('a misread amount shows up as a balance mismatch', () {
      final lines = [
        ln('Date Particulars Debit Credit Balance', [w('Date', 30, 20), w('Particulars', 100, 50), w('Debit', 300, 25), w('Credit', 360, 28), w('Balance', 430, 35)]),
        ln('01-01-2026 Shop', [w('01-01-2026', 30, 52), w('Shop', 100, 25)]),
        ln('100.00', [w('100.00', 300, 30)]),
        ln('900.00', [w('900.00', 430, 30)]),
        ln('02-01-2026 Shop', [w('02-01-2026', 30, 52), w('Shop', 100, 25)]),
        ln('10.00', [w('10.00', 300, 25)]),
        ln('800.00', [w('800.00', 430, 30)]),
      ];
      // Second row says 10.00 but the balance fell by 100.00.
      expect(TablePdfParser.parse(lines).totalsMatch, isFalse);
    });

    test('a page that is not a transaction table is not accepted', () {
      expect(TablePdfParser.looksLikeTable([ln('Hotel booking confirmation Date Balance', [w('Date', 30), w('Balance', 100)])]), isFalse);
    });
  });

  group('Wrong kind of PDF', () {
    test('is rejected from the first page, without reading every page', () async {
      final doc = PdfDocument();
      for (var page = 0; page < 80; page++) {
        final graphics = doc.pages.add().graphics;
        for (var line = 0; line < 40; line++) {
          graphics.drawString('Page $page line $line: account summary and charges', PdfStandardFont(PdfFontFamily.helvetica, 10),
              bounds: Rect.fromLTWH(20, 15.0 * line, 500, 14));
        }
      }
      final bytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final watch = Stopwatch()..start();
      await expectLater(
        StatementReader.read(fileName: 'report.pdf', bytes: bytes),
        throwsA(isA<StatementFormatException>().having((e) => e.message, 'message', contains('isn\'t a Google Pay or bank account statement'))),
      );
      watch.stop();
      // ignore: avoid_print
      print('Rejected an 80 page PDF in ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('CSV', () {
    test('bank statement with debit and credit columns', () {
      const csv = 'Account Statement for XX1234\n'
          'Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance\n'
          '24/10/2026,24/10/2026,UPI/SWIGGY/528712345678/Food,528712345678,349.00,,10000.00\n'
          '21/10/2026,21/10/2026,SALARY CREDIT ACME LTD,,,"45,000.00","55,000.00"\n'
          'Closing balance,,,,,,\n';
      final parsed = CsvStatementParser.parse(csv);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].amount, 349);
      expect(parsed.items[0].upiRef, '528712345678');
      expect(parsed.items[0].date, DateTime(2026, 10, 24));
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 45000);
      expect(parsed.totalsMatch, isNull);
    });

    test('single signed amount column with a type column', () {
      const csv = 'Date;Details;Amount;Type\n'
          '2026-10-03;Netflix;-649.00;Debit\n'
          '2026-10-05;Refund from shop;200;Credit\n';
      final parsed = CsvStatementParser.parse(csv);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].amount, 649);
      expect(parsed.items[1].isIncome, isTrue);
    });

    test('rejects a file without the needed columns', () {
      expect(() => CsvStatementParser.parse('Name,Age\nA,3\n'), throwsA(anything));
    });

    test('parses common date styles', () {
      expect(CsvStatementParser.parseDate('05-Oct-2026'), DateTime(2026, 10, 5));
      expect(CsvStatementParser.parseDate('5 Oct 26'), DateTime(2026, 10, 5));
      expect(CsvStatementParser.parseDate('Oct 5, 2026'), DateTime(2026, 10, 5));
      expect(CsvStatementParser.parseDate('05/10/2026 02:30 PM'), DateTime(2026, 10, 5, 14, 30));
      expect(CsvStatementParser.parseDate('hello'), isNull);
    });
  });

  group('CSV from other apps', () {
    test('Paytm style: signed Rs amounts and a UPI Ref No. column', () {
      const csv = 'Date,Time,Name,Transaction Details,Your Account,Amount,UPI Ref No.,Order ID,Remarks,Tag,Comment\n'
          '05/10/2026,14:30:12,Swiggy,Paid to Swiggy,HDFC Bank - 1234,"- Rs.1,200.50",528712345678,,,,\n'
          '06/10/2026,09:00:00,Ravi Kumar,Received from Ravi Kumar,HDFC Bank - 1234,+ Rs.500,528712345679,,,,\n';
      final parsed = CsvStatementParser.parse(csv);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].amount, 1200.50);
      expect(parsed.items[0].upiRef, '528712345678');
      expect(parsed.items[0].description, 'Paid to Swiggy');
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 500);
    });

    test('HDFC style: Withdrawal Amt. and Deposit Amt. with two digit years', () {
      const csv = 'Date,Narration,Chq./Ref.No.,Value Dt,Withdrawal Amt.,Deposit Amt.,Closing Balance\n'
          '24/10/26,UPI-ZOMATO-ZOMATO@HDFC-528712345678-PAYMENT,0000528712345678,24/10/26,"1,249.00",,"8,751.00"\n'
          '25/10/26,NEFT CR-ACME LTD-SALARY,N298261234567,25/10/26,,"60,000.00","68,751.00"\n';
      final parsed = CsvStatementParser.parse(csv);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].amount, 1249);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].date, DateTime(2026, 10, 24));
      expect(parsed.items[1].amount, 60000);
      expect(parsed.items[1].isIncome, isTrue);
    });

    test('tab separated file with a BOM and Windows line endings', () {
      const csv = '\uFEFFDate\tDescription\tAmount\tDr/Cr\r\n03-Oct-2026\tRent\t15000\tDR\r\n04-Oct-2026\tRefund\t300\tCR\r\n';
      final parsed = CsvStatementParser.parse(csv);

      expect(parsed.items.length, 2);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[1].isIncome, isTrue);
    });
  });

  group('Excel', () {
    test('reads an .xlsx bank statement with real date cells', () async {
      final bytes = File('test/fixtures/bank_statement.xlsx').readAsBytesSync();
      final parsed = await StatementReader.read(fileName: 'statement.xlsx', bytes: bytes);

      expect(parsed.items.length, 3);
      expect(parsed.items[0].date, DateTime(2026, 10, 24, 14, 30));
      expect(parsed.items[0].amount, 349);
      expect(parsed.items[0].isIncome, isFalse);
      expect(parsed.items[0].upiRef, '528712345678');
      expect(parsed.items[1].isIncome, isTrue);
      expect(parsed.items[1].amount, 45000);
      expect(parsed.items[2].description, contains('Netflix'));
    });

    test('rejects a file that is not a real .xlsx', () async {
      expect(
        () => StatementReader.read(fileName: 'old.xlsx', bytes: Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<StatementFormatException>()),
      );
    });
  });

  group('category suggestions', () {
    test('matches known merchants and falls back to Other', () {
      expect(CategorySuggester.suggest('UPI/SWIGGY', TransactionType.expense), 'Food');
      expect(CategorySuggester.suggest('BIGBASKET', TransactionType.expense), 'Groceries');
      expect(CategorySuggester.suggest('Netflix', TransactionType.expense), 'Subscriptions');
      expect(CategorySuggester.suggest('Ravi Kumar', TransactionType.expense), 'Other');
      expect(CategorySuggester.suggest('Salary credit', TransactionType.income), 'Salary');
      expect(CategorySuggester.suggest('Ravi Kumar', TransactionType.income), 'Other Income');
    });

    test('remembered payees win over rules', () {
      final memory = {CategorySuggester.normalise('Swiggy'): 'Gifts & Donations'};
      expect(CategorySuggester.suggest('Swiggy', TransactionType.expense, memory: memory), 'Gifts & Donations');
    });
  });
}
