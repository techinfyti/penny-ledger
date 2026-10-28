import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:penny_ledger/models/expense.dart';
import 'package:penny_ledger/services/statement_import/category_suggester.dart';
import 'package:penny_ledger/services/statement_import/csv_statement_parser.dart';
import 'package:penny_ledger/services/statement_import/imported_transaction.dart';
import 'package:penny_ledger/services/statement_import/statement_reader.dart';

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
        throwsA(isA<StatementFormatException>().having((e) => e.message, 'message', contains('isn\'t a Google Pay statement'))),
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
