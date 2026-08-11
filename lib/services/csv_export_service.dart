import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';

class CsvExportService {
  Future<void> shareCsv({
    required String filenamePrefix,
    required List<Expense> transactions,
    Map<String, String> groupNames = const {},
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Date,Category,Type,Amount,Payment Method,Name,Group,Note');
    final sorted = [...transactions]..sort((a, b) => b.date.compareTo(a.date));
    for (final t in sorted) {
      final date =
          '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}';
      final type = t.type == TransactionType.income ? 'Income' : 'Expense';
      final note = t.note.replaceAll('"', '""');
      final category = t.category.replaceAll('"', '""');
      final name = t.personName.replaceAll('"', '""');
      final group = (groupNames[t.groupId] ?? '').replaceAll('"', '""');
      buffer.writeln(
        '$date,"$category",$type,${t.amount.toStringAsFixed(2)},${t.paymentMethod},"$name","$group","$note"',
      );
    }

    final dir = await getTemporaryDirectory();
    final safeName = filenamePrefix.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File('${dir.path}/pennyledger_$safeName.csv');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles([XFile(file.path)], subject: 'PennyLedger export');
  }
}
