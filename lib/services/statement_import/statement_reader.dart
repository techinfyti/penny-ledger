import 'dart:convert';
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
    if (lower.endsWith('.pdf')) return _readPdf(bytes, pdfPassword);
    if (lower.endsWith('.xlsx')) {
      return CsvStatementParser.parseRows(XlsxReader.readRows(bytes), sourceLabel: 'Excel statement');
    }
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      return CsvStatementParser.parse(utf8.decode(bytes, allowMalformed: true));
    }
    throw StatementFormatException('Choose a PDF, Excel (.xlsx) or CSV file.');
  }

  static ParsedStatement _readPdf(Uint8List bytes, String? password) {
    late final List<String> lines;
    PdfDocument? document;
    try {
      document = password == null ? PdfDocument(inputBytes: bytes) : PdfDocument(inputBytes: bytes, password: password);
      // Line mode keeps Google Pay's characters in reading order; plain text mode scrambles them.
      lines = PdfTextExtractor(document).extractTextLines().map((l) => l.text).toList();
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('password') || message.contains('encrypt') || message.contains('decrypt')) {
        throw StatementPasswordRequired(wrongPassword: password != null);
      }
      throw StatementFormatException('Couldn\'t read this PDF.');
    } finally {
      document?.dispose();
    }

    if (!GpayPdfParser.looksLikeGpay(lines.join('\n'))) {
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
