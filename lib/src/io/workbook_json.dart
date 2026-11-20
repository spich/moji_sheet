import 'dart:convert';
import 'dart:ui' show Color;

import 'package:worksheet/worksheet.dart' hide FormulaFunction;
import 'package:worksheet_formula/worksheet_formula.dart' show FormulaEngine;

import '../locale/sheet_locale.dart';
import '../model/sheet_chart.dart';
import '../model/workbook.dart';

/// Saving a [Workbook] to JSON and loading it back.
///
/// Stored per sheet: values and formulas, number formats, cell background,
/// alignment and wrapping, merged cells, resized columns and rows, charts.
/// Not stored in this version: cell borders and rich text within a cell.
///
/// The format carries a [version]; a file written by a newer version is
/// refused instead of being read wrongly.
class WorkbookJson {
  const WorkbookJson._();

  static const formatName = 'moji_sheet';
  static const version = 1;

  static String encode(Workbook workbook, {bool pretty = false}) {
    final map = toMap(workbook);
    return pretty
        ? const JsonEncoder.withIndent(' ').convert(map)
        : jsonEncode(map);
  }

  static Workbook decode(String json, {FormulaEngine? engine}) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) throw const FormatException('Not a moji_sheet workbook.');
    return fromMap(Map<String, dynamic>.from(decoded), engine: engine);
  }

  static Map<String, dynamic> toMap(Workbook workbook) => {
        'format': formatName,
        'version': version,
        'locale': workbook.locale.code,
        'sheets': [for (final s in workbook.sheets) _sheetToMap(s)],
      };

  static Workbook fromMap(Map<String, dynamic> map, {FormulaEngine? engine}) {
    if (map['format'] != formatName) {
      throw const FormatException('Not a moji_sheet workbook.');
    }
    final v = map['version'];
    if (v is! int || v > version) {
      throw FormatException(
        'Workbook version $v is newer than this package reads ($version).',
      );
    }
    final sheets = <Sheet>[
      for (final s in (map['sheets'] as List? ?? const []))
        _sheetFromMap(Map<String, dynamic>.from(s as Map)),
    ];
    return Workbook(
      locale: SheetLocale.forCode(map['locale'] as String?),
      sheets: sheets.isEmpty ? null : sheets,
      engine: engine,
    );
  }

  // ── Sheet ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _sheetToMap(Sheet s) {
    final cells = <String, Map<String, dynamic>>{};
    Map<String, dynamic> at(CellCoordinate c) =>
        cells.putIfAbsent(c.toNotation(), () => <String, dynamic>{});

    final all = s.fullRange;
    for (final e in s.raw.getCellsInRange(all)) {
      _valueToMap(e.value, at(e.key));
    }
    for (final e in s.raw.getFormatsInRange(all)) {
      at(e.key)['f'] = {'t': e.value.type.name, 'c': e.value.formatCode};
    }
    for (final e in s.raw.getStylesInRange(all)) {
      final style = _styleToMap(e.value);
      if (style.isNotEmpty) at(e.key)['s'] = style;
    }
    return {
      'name': s.name,
      'rows': s.rowCount,
      'columns': s.columnCount,
      'cells': cells,
      if (s.columnWidths.isNotEmpty)
        'columnWidths': {
          for (final e in s.columnWidths.entries) '${e.key}': e.value,
        },
      if (s.rowHeights.isNotEmpty)
        'rowHeights': {
          for (final e in s.rowHeights.entries) '${e.key}': e.value,
        },
      if (!s.raw.mergedCells.isEmpty)
        'merges': [
          for (final m in s.raw.mergedCells.regions) _rangeText(m.range),
        ],
      if (s.charts.isNotEmpty)
        'charts': [
          for (final c in s.charts)
            {
              'type': c.type.name,
              'range': _rangeText(c.range),
              'title': c.title,
              'header': c.firstRowIsHeader,
              'labels': c.firstColumnIsLabels,
            },
        ],
    };
  }

  static Sheet _sheetFromMap(Map<String, dynamic> m) {
    Map<int, double> sizes(Object? o) => {
          if (o is Map)
            for (final e in o.entries)
              if (int.tryParse('${e.key}') != null && e.value is num)
                int.parse('${e.key}'): (e.value as num).toDouble(),
        };
    final sheet = Sheet(
      name: '${m['name'] ?? 'Sheet'}',
      rowCount: (m['rows'] as num?)?.toInt() ?? 200,
      columnCount: (m['columns'] as num?)?.toInt() ?? 26,
      columnWidths: sizes(m['columnWidths']),
      rowHeights: sizes(m['rowHeights']),
    );
    final cells = m['cells'];
    if (cells is Map) {
      sheet.data.batchUpdateRaw((b) {
        for (final e in cells.entries) {
          final coord = _coord('${e.key}');
          final cell = e.value;
          if (coord == null || cell is! Map) continue;
          if (coord.row >= sheet.rowCount || coord.column >= sheet.columnCount) {
            continue;
          }
          final value = _valueFromMap(cell);
          if (value != null) b.setCell(coord, value);
          final f = cell['f'];
          if (f is Map && f['c'] is String) {
            b.setFormat(
              coord,
              CellFormat(
                type: CellFormatType.values.firstWhere(
                  (t) => t.name == f['t'],
                  orElse: () => CellFormatType.custom,
                ),
                formatCode: f['c'] as String,
              ),
            );
          }
          final st = cell['s'];
          if (st is Map) b.setStyle(coord, _styleFromMap(st));
        }
      });
    }
    for (final r in (m['merges'] as List? ?? const [])) {
      final range = _range('$r');
      if (range != null) sheet.raw.mergeCells(range);
    }
    for (final c in (m['charts'] as List? ?? const [])) {
      if (c is! Map) continue;
      final range = _range('${c['range']}');
      if (range == null) continue;
      sheet.charts.add(
        SheetChart(
          type: SheetChartType.values.firstWhere(
            (t) => t.name == c['type'],
            orElse: () => SheetChartType.bar,
          ),
          range: range,
          title: '${c['title'] ?? ''}',
          firstRowIsHeader: c['header'] != false,
          firstColumnIsLabels: c['labels'] != false,
        ),
      );
    }
    return sheet;
  }

  // ── Values ─────────────────────────────────────────────────────────────

  static void _valueToMap(CellValue v, Map<String, dynamic> out) {
    switch (v.type) {
      case CellValueType.number:
        out['v'] = v.asDouble;
      case CellValueType.text:
        out['v'] = v.rawValue as String;
        out['t'] = 's';
      case CellValueType.boolean:
        out['v'] = v.rawValue as bool;
      case CellValueType.formula:
        out['v'] = v.rawValue as String;
        out['t'] = 'f';
      case CellValueType.error:
        out['v'] = v.rawValue as String;
        out['t'] = 'e';
      case CellValueType.date:
        out['v'] = v.asDateTime.toIso8601String();
        out['t'] = 'd';
      case CellValueType.duration:
        out['v'] = v.asDuration.inMicroseconds;
        out['t'] = 'u';
    }
  }

  static CellValue? _valueFromMap(Map cell) {
    final v = cell['v'];
    if (v == null) return null;
    switch (cell['t']) {
      case 'f':
        return CellValue.formula('$v');
      case 'e':
        return CellValue.error('$v');
      case 'd':
        final d = DateTime.tryParse('$v');
        return d == null ? CellValue.text('$v') : CellValue.date(d);
      case 'u':
        return v is num
            ? CellValue.duration(Duration(microseconds: v.toInt()))
            : null;
      case 's':
        return CellValue.text('$v');
    }
    if (v is num) return CellValue.number(v);
    if (v is bool) return CellValue.boolean(v);
    return CellValue.text('$v');
  }

  // ── Style ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _styleToMap(CellStyle s) => {
        if (s.backgroundColor != null) 'bg': _hex(s.backgroundColor!),
        if (s.textAlignment != null) 'a': s.textAlignment!.name,
        if (s.verticalAlignment != null) 'va': s.verticalAlignment!.name,
        if (s.wrapText != null) 'w': s.wrapText,
      };

  static CellStyle _styleFromMap(Map m) => CellStyle(
        backgroundColor: _color(m['bg']),
        textAlignment: _byName(CellTextAlignment.values, m['a']),
        verticalAlignment: _byName(CellVerticalAlignment.values, m['va']),
        wrapText: m['w'] is bool ? m['w'] as bool : null,
      );

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static Color? _color(Object? o) {
    if (o is! String || !o.startsWith('#')) return null;
    final n = int.tryParse(o.substring(1), radix: 16);
    if (n == null) return null;
    return Color(o.length == 7 ? 0xFF000000 | n : n);
  }

  // ── Coordinates ────────────────────────────────────────────────────────

  static CellCoordinate? _coord(String notation) {
    try {
      final a = A1.parse(notation);
      return CellCoordinate(a.row, a.column);
    } catch (_) {
      return null;
    }
  }

  static String _rangeText(CellRange r) =>
      '${CellCoordinate(r.startRow, r.startColumn).toNotation()}:'
      '${CellCoordinate(r.endRow, r.endColumn).toNotation()}';

  static CellRange? _range(String text) {
    final p = text.split(':');
    final a = _coord(p.first);
    final b = _coord(p.last);
    if (a == null || b == null) return null;
    return CellRange(
      a.row < b.row ? a.row : b.row,
      a.column < b.column ? a.column : b.column,
      a.row < b.row ? b.row : a.row,
      a.column < b.column ? b.column : a.column,
    );
  }
}
