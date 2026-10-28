import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'csv_statement_parser.dart';
import 'gpay_pdf_parser.dart';
import 'imported_transaction.dart';
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

  static ParsedStatement _readPdf(Uint8List bytes, String? password) {
    var isGpay = false;
    final lines = <String>[];
    PdfDocument? document;
    try {
      document = password == null ? PdfDocument(inputBytes: bytes) : PdfDocument(inputBytes: bytes, password: password);
      final extractor = PdfTextExtractor(document);
      // Line mode keeps Google Pay's characters in reading order; plain text mode scrambles them.
      // The first page is checked before reading the rest, so a PDF of the wrong kind is rejected quickly.
      lines.addAll(extractor.extractTextLines(startPageIndex: 0, endPageIndex: 0).map((l) => l.text));
      isGpay = GpayPdfParser.looksLikeGpay(lines.join('\n'));
      if (isGpay && document.pages.count > 1) {
        lines.addAll(extractor.extractTextLines(startPageIndex: 1, endPageIndex: document.pages.count - 1).map((l) => l.text));
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

    if (!isGpay) {
      throw StatementFormatException(
        'This PDF isn\'t a Google Pay statement. For bank or Paytm statements, download the CSV or Excel (.xlsx) version and import that.',
      );
    }
    final parsed = GpayPdfParser.parse(lines);
    if (parsed.items.isEmpty) {
      throw StatementFormatException('No transactions found in this statement.');
    }
    return parsed;
  }
}
