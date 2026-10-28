import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'imported_transaction.dart';

/// Turns the first worksheet of an .xlsx file into rows of text, so Excel
/// statements can go through the same column matching as CSV files.
/// Dates are written as yyyy-MM-dd[ HH:mm] so the date parser reads them.
class XlsxReader {
  static List<List<String>> readRows(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw StatementFormatException(
        'Couldn\'t read this Excel file. Old .xls files aren\'t supported: open it in Excel and save as .xlsx or .csv.',
      );
    }

    String? textOf(String path) {
      final file = archive.findFile(path);
      return file == null ? null : utf8.decode(file.content as List<int>, allowMalformed: true);
    }

    final sheetPath = _firstSheetPath(archive, textOf);
    final sheetXml = sheetPath == null ? null : textOf(sheetPath);
    if (sheetXml == null) {
      throw StatementFormatException('This Excel file has no readable sheet.');
    }

    final shared = _sharedStrings(textOf('xl/sharedStrings.xml'));
    final dateStyles = _dateStyles(textOf('xl/styles.xml'));

    final rows = <List<String>>[];
    final sheet = XmlDocument.parse(sheetXml);
    for (final row in sheet.findAllElements('row')) {
      final cells = <int, String>{};
      var maxCol = -1;
      var next = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? next : _columnIndex(ref);
        next = col + 1;
        final value = _cellText(c, shared, dateStyles);
        if (value.isNotEmpty) {
          cells[col] = value;
          if (col > maxCol) maxCol = col;
        }
      }
      if (maxCol < 0) continue;
      rows.add([for (var i = 0; i <= maxCol; i++) cells[i] ?? '']);
    }
    return rows;
  }

  static String? _firstSheetPath(Archive archive, String? Function(String) textOf) {
    final workbook = textOf('xl/workbook.xml');
    final rels = textOf('xl/_rels/workbook.xml.rels');
    if (workbook != null && rels != null) {
      final firstSheet = XmlDocument.parse(workbook).findAllElements('sheet').firstOrNull;
      final rid = firstSheet?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
      if (rid != null) {
        for (final rel in XmlDocument.parse(rels).findAllElements('Relationship')) {
          if (rel.getAttribute('Id') == rid) {
            final target = rel.getAttribute('Target') ?? '';
            return target.startsWith('/') ? target.substring(1) : 'xl/$target';
          }
        }
      }
    }
    for (final f in archive) {
      if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) return f.name;
    }
    return null;
  }

  static List<String> _sharedStrings(String? xml) {
    if (xml == null) return const [];
    return [
      for (final si in XmlDocument.parse(xml).findAllElements('si'))
        si.findAllElements('t').map((t) => t.innerText).join(),
    ];
  }

  /// Style indexes whose number format is a date or time.
  static Set<int> _dateStyles(String? xml) {
    if (xml == null) return {};
    final doc = XmlDocument.parse(xml);
    final customDate = <int>{};
    for (final f in doc.findAllElements('numFmt')) {
      final id = int.tryParse(f.getAttribute('numFmtId') ?? '');
      final code = (f.getAttribute('formatCode') ?? '').toLowerCase().replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]'), '');
      if (id != null && RegExp(r'[dmyh]').hasMatch(code) && !code.contains('0.0') && !code.contains('#')) customDate.add(id);
    }
    bool builtInDate(int id) => (id >= 14 && id <= 22) || (id >= 45 && id <= 47);

    final result = <int>{};
    final xfs = doc.findAllElements('cellXfs').firstOrNull?.findElements('xf').toList() ?? const [];
    for (var i = 0; i < xfs.length; i++) {
      final id = int.tryParse(xfs[i].getAttribute('numFmtId') ?? '');
      if (id != null && (builtInDate(id) || customDate.contains(id))) result.add(i);
    }
    return result;
  }

  static String _cellText(XmlElement c, List<String> shared, Set<int> dateStyles) {
    final type = c.getAttribute('t');
    if (type == 'inlineStr') return c.findAllElements('t').map((t) => t.innerText).join().trim();
    final raw = c.findElements('v').firstOrNull?.innerText.trim() ?? '';
    if (raw.isEmpty) return '';
    if (type == 's') {
      final index = int.tryParse(raw);
      return index != null && index < shared.length ? shared[index].trim() : '';
    }
    if (type == 'str' || type == 'b' || type == 'e') return raw;

    final style = int.tryParse(c.getAttribute('s') ?? '');
    final serial = double.tryParse(raw);
    if (serial != null && style != null && dateStyles.contains(style)) {
      final whole = serial.floor();
      final minutes = ((serial - whole) * 24 * 60).round();
      final date = DateTime(1899, 12, 30).add(Duration(days: whole, minutes: minutes));
      final day = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      if (minutes == 0) return day;
      return '$day ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return raw;
  }

  /// "AB12" -> 27 (zero based).
  static int _columnIndex(String ref) {
    var index = 0;
    for (final unit in ref.codeUnits) {
      if (unit >= 65 && unit <= 90) {
        index = index * 26 + (unit - 64);
      } else {
        break;
      }
    }
    return index - 1;
  }
}
