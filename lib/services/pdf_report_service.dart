import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/expense.dart';

class PdfReportService {
  Future<void> shareReport({
    required String title,
    required String subtitle,
    required List<Expense> transactions,
    required String currencyCode,
    Map<String, String> groupNames = const {},
  }) async {
    final bytes = await _buildPdf(
      title: title,
      subtitle: subtitle,
      transactions: transactions,
      currencyCode: currencyCode,
      groupNames: groupNames,
    );
    final safeSubtitle = subtitle.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    await Printing.sharePdf(bytes: bytes, filename: 'pennyledger_$safeSubtitle.pdf');
  }

  Future<void> printReport({
    required String title,
    required String subtitle,
    required List<Expense> transactions,
    required String currencyCode,
    Map<String, String> groupNames = const {},
  }) async {
    final bytes = await _buildPdf(
      title: title,
      subtitle: subtitle,
      transactions: transactions,
      currencyCode: currencyCode,
      groupNames: groupNames,
    );
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  Future<Uint8List> _buildPdf({
    required String title,
    required String subtitle,
    required List<Expense> transactions,
    required String currencyCode,
    Map<String, String> groupNames = const {},
  }) async {
    final doc = pw.Document();
    final dateFormat = DateFormat('MMM d, yyyy');

    final income = transactions
        .where((e) => e.type == TransactionType.income)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final expense = transactions
        .where((e) => e.type == TransactionType.expense)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final net = income - expense;

    final sorted = [...transactions]..sort((a, b) => b.date.compareTo(a.date));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _summaryTile('Income', income, PdfColors.green800, currencyCode),
              _summaryTile('Expense', expense, PdfColors.red800, currencyCode),
              _summaryTile('Net', net, net >= 0 ? PdfColors.green800 : PdfColors.red800, currencyCode),
            ],
          ),
          pw.SizedBox(height: 24),
          if (sorted.isEmpty)
            pw.Text('No transactions in this period.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.5),
                4: pw.FlexColumnWidth(2),
                5: pw.FlexColumnWidth(3),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Date', bold: true),
                    _cell('Category', bold: true),
                    _cell('Group', bold: true),
                    _cell('Type', bold: true),
                    _cell('Amount', bold: true),
                    _cell('Note', bold: true),
                  ],
                ),
                for (final t in sorted)
                  pw.TableRow(
                    children: [
                      _cell(dateFormat.format(t.date)),
                      _cell(t.category),
                      _cell(groupNames[t.groupId] ?? ''),
                      _cell(t.type == TransactionType.income ? 'Income' : 'Expense'),
                      _cell(
                        '${t.type == TransactionType.income ? '+' : '-'}$currencyCode ${t.amount.toStringAsFixed(2)}',
                      ),
                      _cell(t.note),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _summaryTile(String label, double value, PdfColor color, String currencyCode) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.Text(
          '$currencyCode ${value.toStringAsFixed(2)}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: color),
        ),
      ],
    );
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }
}
