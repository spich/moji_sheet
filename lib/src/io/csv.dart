import 'package:worksheet/worksheet.dart' hide FormulaFunction;

import '../locale/sheet_locale.dart';
import '../model/workbook.dart';

/// Reading and writing delimiter-separated text.
class SheetCsv {
  const SheetCsv._();

  /// The delimiter [text] most plausibly uses: the candidate that splits the
  /// first lines into the same number of fields (more than one), preferring
  /// the one with most fields. Falls back to a comma.
  static String detectDelimiter(String text) {
    const candidates = [';', ',', '\t', '|'];
    var best = ',';
    var bestScore = 0;
    for (final d in candidates) {
      final rows = parse(text, delimiter: d, maxRows: 10);
      if (rows.isEmpty) continue;
      final n = rows.first.length;
      if (n < 2) continue;
      final consistent = rows.where((r) => r.length == n).length;
      final score = consistent * 100 + n;
      if (consistent * 2 >= rows.length && score > bestScore) {
        best = d;
        bestScore = score;
      }
    }
    return best;
  }

  /// Splits [text] into rows of fields (RFC 4180: quoted fields, doubled
  /// quotes, line breaks inside quotes; CRLF, LF or CR line ends; an optional
  /// byte-order mark).
  static List<List<String>> parse(
    String text, {
    String? delimiter,
    int? maxRows,
  }) {
    var s = text;
    if (s.startsWith('﻿')) s = s.substring(1);
    final d = delimiter ?? detectDelimiter(s);
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var fieldWasQuoted = false;
    var i = 0;

    void endField() {
      row.add(field.toString());
      field.clear();
      fieldWasQuoted = false;
    }

    bool endRow() {
      endField();
      // A line with nothing on it is not a row.
      if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
      row = <String>[];
      return maxRows != null && rows.length >= maxRows;
    }

    while (i < s.length) {
      final ch = s[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          quoted = false;
        } else {
          field.write(ch);
        }
        i++;
        continue;
      }
      if (ch == '"' && field.isEmpty && !fieldWasQuoted) {
        quoted = true;
        fieldWasQuoted = true;
      } else if (s.startsWith(d, i)) {
        endField();
        i += d.length;
        continue;
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        if (endRow()) return rows;
      } else {
        field.write(ch);
      }
      i++;
    }
    if (field.isNotEmpty || row.isNotEmpty || fieldWasQuoted) endRow();
    return rows;
  }

  /// Builds a sheet from CSV [text].
  ///
  /// Each field is typed the way typing it into a cell would be: numbers and
  /// dates in [locale], booleans, otherwise text. A leading `=` is kept as
  /// text unless [allowFormulas] — a CSV from elsewhere should not be able to
  /// plant formulas.
  static Sheet toSheet(
    String text, {
    required String name,
    SheetLocale locale = SheetLocale.enUs,
    String? delimiter,
    bool allowFormulas = false,
    int minRows = 200,
    int minColumns = 26,
  }) {
    final rows = parse(text, delimiter: delimiter);
    var columns = 0;
    for (final r in rows) {
      if (r.length > columns) columns = r.length;
    }
    final sheet = Sheet(
      name: name,
      rowCount: rows.length + 50 > minRows ? rows.length + 50 : minRows,
      columnCount: columns + 5 > minColumns ? columns + 5 : minColumns,
    );
    final dateParser =
        AnyDate(info: DateParserInfo(dayFirst: locale.format.dayFirst));
    sheet.data.batchUpdateRaw((b) {
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          final field = rows[r][c];
          if (field.trim().isEmpty) continue;
          final coord = CellCoordinate(r, c);
          final identifier = _looksLikeIdentifier(field);
          final number = identifier ? null : locale.parseNumber(field);
          if (number != null) {
            b.setCell(coord, CellValue.number(number.value));
            if (number.format != null) b.setFormat(coord, number.format);
            continue;
          }
          // Identifiers such as "00123" or "+385…" stay text.
          final value = identifier
              ? null
              : CellValue.parse(
                  field,
                  allowFormulas: allowFormulas,
                  dateParser: dateParser,
                );
          b.setCell(coord, value ?? CellValue.text(field));
        }
      }
    });
    return sheet;
  }

  static bool _looksLikeIdentifier(String field) {
    final t = field.trim();
    return RegExp(r'^0\d+$').hasMatch(t) || RegExp(r'^\+\d').hasMatch(t);
  }

  /// Writes [range] of [sheet] (its used range by default) as CSV.
  ///
  /// With [formatted] cells are written as displayed; otherwise numbers use
  /// the locale's decimal separator without grouping and dates are ISO 8601,
  /// so the file reads back to the same values. Formula cells are written as
  /// their results.
  static String fromSheet(
    Sheet sheet, {
    CellRange? range,
    String? delimiter,
    bool formatted = false,
    String lineEnd = '\r\n',
  }) {
    final locale = sheet.workbook?.locale ?? SheetLocale.enUs;
    final d = delimiter ?? locale.csvDelimiter;
    final r = range ?? sheet.usedRange;
    if (r == null) return '';
    final out = StringBuffer();
    for (var row = r.startRow; row <= r.endRow; row++) {
      final fields = <String>[];
      for (var col = r.startColumn; col <= r.endColumn; col++) {
        fields.add(_escape(_fieldText(sheet, row, col, locale, formatted), d));
      }
      out.write(fields.join(d));
      out.write(lineEnd);
    }
    return out.toString();
  }

  static String _fieldText(
    Sheet sheet,
    int row,
    int col,
    SheetLocale locale,
    bool formatted,
  ) {
    if (formatted) return sheet.displayAt(row, col);
    final v = sheet.valueAt(row, col);
    if (v == null) return '';
    if (v.isNumber) return locale.formatNumber(v.asDouble, maxDecimals: 10);
    if (v.isDate) {
      final d = v.asDateTime;
      final date = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      if (d.hour == 0 && d.minute == 0 && d.second == 0) return date;
      return '$date ${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}:'
          '${d.second.toString().padLeft(2, '0')}';
    }
    return v.displayValue;
  }

  static String _escape(String field, String delimiter) {
    final needsQuotes = field.contains(delimiter) ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r') ||
        field.startsWith(' ') ||
        field.endsWith(' ');
    return needsQuotes ? '"${field.replaceAll('"', '""')}"' : field;
  }
}
