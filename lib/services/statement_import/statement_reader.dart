import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'axis_pdf_parser.dart';
import 'bank_pdf_parser.dart';
import 'csv_statement_parser.dart';
import 'gpay_pdf_parser.dart';
import 'imported_transaction.dart';
import 'pdf_lines.dart';
import 'table_pdf_parser.dart';
import 'xlsx_reader.dart';

class StatementReader {
  static Future<ParsedStatement> read({
    required String fileName,
    required Uint8List bytes,
    String? pdfPassword,
  }) async {
    final lower = fileName.toLowerCase();
    // Reading a PDF is slow, so it runs off the main thread and the spinner keeps moving.
    if (lower.endsWith('.pdf')) return Isolate.run(() => _readPdf(bytes, pdfPassword));
    if (lower.endsWith('.xlsx')) {
      return CsvStatementParser.parseRows(XlsxReader.readRows(bytes), sourceLabel: 'Excel statement');
    }
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      return CsvStatementParser.parse(utf8.decode(bytes, allowMalformed: true));
    }
    throw StatementFormatException('Choose a PDF, Excel (.xlsx) or CSV file.');
  }

  static List<PdfLine> _toLines(List<TextLine> lines) => [
        for (final l in lines) PdfLine(l.text, [for (final w in l.wordCollection) PdfWord(w.text, w.bounds.left, w.bounds.width)]),
      ];

  static ParsedStatement _readPdf(Uint8List bytes, String? password) {
    var isGpay = false;
    var isBank = false;
    var isAxis = false;
    var isTable = false;
    final lines = <PdfLine>[];
    PdfDocument? document;
    try {
      document = password == null ? PdfDocument(inputBytes: bytes) : PdfDocument(inputBytes: bytes, password: password);
      final extractor = PdfTextExtractor(document);
      // Line mode keeps Google Pay's characters in reading order; plain text mode scrambles them.
      // The first page is checked before reading the rest, so a PDF of the wrong kind is rejected quickly.
      lines.addAll(_toLines(extractor.extractTextLines(startPageIndex: 0, endPageIndex: 0)));
      isGpay = GpayPdfParser.looksLikeGpay(lines.map((l) => l.text).join('\n'));
      isBank = !isGpay && BankPdfParser.looksLikeBank(lines);
      isAxis = !isGpay && !isBank && AxisPdfParser.looksLikeAxis(lines);
      isTable = !isGpay && !isBank && !isAxis && TablePdfParser.looksLikeTable(lines);
      if ((isGpay || isBank || isAxis || isTable) && document.pages.count > 1) {
        lines.addAll(_toLines(extractor.extractTextLines(startPageIndex: 1, endPageIndex: document.pages.count - 1)));
      }
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('password') || message.contains('encrypt') || message.contains('decrypt')) {
        throw StatementPasswordRequired(wrongPassword: password != null);
      }
      throw StatementFormatException('Couldn\'t read this PDF.');
    } finally {
      document?.dispose();
    }

    if (!isGpay && !isBank && !isAxis && !isTable) {
      throw StatementFormatException(
        'This PDF isn\'t a Google Pay or bank account statement we can read. Download the CSV or Excel (.xlsx) version from your bank and import that.',
      );
    }
    final parsed = isGpay
        ? GpayPdfParser.parse(lines.map((l) => l.text).toList())
        : isAxis
            ? AxisPdfParser.parse(lines)
            : isTable
                ? TablePdfParser.parse(lines)
                : BankPdfParser.parse(lines);
    if (parsed.items.isEmpty) {
      throw StatementFormatException('No transactions found in this statement.');
    }
    return parsed;
  }
}
