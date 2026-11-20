import 'package:flutter/foundation.dart';
import 'package:worksheet/worksheet.dart' hide FormulaFunction;
import 'package:worksheet_formula/worksheet_formula.dart';

import '../formula/sheet_refs.dart';
import '../locale/sheet_locale.dart';
import 'sheet_chart.dart';
import 'sheet_data.dart';

/// One sheet of a [Workbook]: a named grid of cells with its own column
/// widths, row heights and charts.
class Sheet {
  Sheet({
    required this.name,
    int rowCount = 200,
    int columnCount = 26,
    Map<int, double>? columnWidths,
    Map<int, double>? rowHeights,
    List<SheetChart>? charts,
  })  : columnWidths = columnWidths ?? {},
        rowHeights = rowHeights ?? {},
        charts = charts ?? [] {
    data = SheetData(
      this,
      SparseWorksheetData(rowCount: rowCount, columnCount: columnCount),
    );
  }

  /// Unique within the workbook. Rename with [Workbook.renameSheet], which
  /// also updates formulas that reference the sheet.
  String name;

  /// The workbook this sheet belongs to; `null` until it is added to one.
  Workbook? workbook;

  /// Cells as the grid reads and writes them (calculated, locale-aware).
  late final SheetData data;

  /// Stored cells (formulas as text).
  SparseWorksheetData get raw => data.raw;

  int get rowCount => data.rowCount;
  int get columnCount => data.columnCount;

  /// Column index → width, for columns the user resized.
  final Map<int, double> columnWidths;

  /// Row index → height, for rows the user resized.
  final Map<int, double> rowHeights;

  final List<SheetChart> charts;

  /// The whole sheet as a range.
  CellRange get fullRange => CellRange(0, 0, rowCount - 1, columnCount - 1);

  /// Smallest range containing every cell that has a value, or `null` for an
  /// empty sheet.
  CellRange? get usedRange {
    int? r0, c0, r1, c1;
    for (final e in raw.getCellsInRange(fullRange)) {
      final c = e.key;
      r0 = r0 == null || c.row < r0 ? c.row : r0;
      r1 = r1 == null || c.row > r1 ? c.row : r1;
      c0 = c0 == null || c.column < c0 ? c.column : c0;
      c1 = c1 == null || c.column > c1 ? c.column : c1;
    }
    if (r0 == null) return null;
    return CellRange(r0, c0!, r1!, c1!);
  }

  /// Sets a cell from user-style input: `=SUM(A1:A3)`, `12,5 %`, `20.11.2026.`,
  /// `true`, or plain text. Empty input clears the cell.
  void setInput(int row, int column, String input) {
    final coord = CellCoordinate(row, column);
    final text = input.trim();
    if (text.isEmpty) {
      data.setCell(coord, null);
      return;
    }
    final locale = workbook?.locale ?? SheetLocale.enUs;
    final number = locale.parseNumber(text);
    if (number != null) {
      data.batchUpdateRaw((b) {
        b.setCell(coord, CellValue.number(number.value));
        if (number.format != null) b.setFormat(coord, number.format);
      });
      return;
    }
    final value = CellValue.parse(
      text,
      dateParser: AnyDate(info: DateParserInfo(dayFirst: locale.format.dayFirst)),
    );
    data.setCell(coord, value ?? CellValue.text(input));
  }

  /// Calculated value of a cell (the formula result for formula cells).
  CellValue? valueAt(int row, int column) =>
      data.getCell(CellCoordinate(row, column));

  /// The text shown in a cell, formatted for the workbook's locale.
  String displayAt(int row, int column) {
    final coord = CellCoordinate(row, column);
    final value = data.getCell(coord);
    if (value == null) return '';
    final format = data.getFormat(coord);
    final locale = workbook?.locale ?? SheetLocale.enUs;
    if (format != null) {
      return format.formatRich(value, locale: locale.format).text;
    }
    if (value.isNumber) return locale.formatNumber(value.asDouble);
    return value.displayValue;
  }

  void dispose() => data.dispose();
}

/// A set of sheets calculated together.
///
/// Formulas may reference other sheets (`=Sheet2!B4`, `=SUM('My data'!A1:A9)`).
/// The workbook notifies listeners when sheets are added, removed, renamed or
/// reordered, and whenever any cell changes.
class Workbook extends ChangeNotifier {
  Workbook({
    this.locale = SheetLocale.enUs,
    List<Sheet>? sheets,
    FormulaEngine? engine,
  }) : engine = engine ?? FormulaEngine() {
    for (final s in sheets ?? [Sheet(name: 'Sheet1')]) {
      _attach(s);
    }
  }

  /// Calculates formulas. Register custom functions on it.
  final FormulaEngine engine;

  /// Regional conventions for typing and displaying numbers and dates.
  SheetLocale locale;

  final List<Sheet> _sheets = [];
  List<Sheet> get sheets => List.unmodifiable(_sheets);

  final Map<String, RewrittenFormula> _rewritten = {};
  final Set<String> _evaluating = {};
  bool _disposed = false;

  void _attach(Sheet s, [int? index]) {
    s.workbook = this;
    if (index == null) {
      _sheets.add(s);
    } else {
      _sheets.insert(index, s);
    }
  }

  Sheet? sheetNamed(String name) {
    final n = name.toLowerCase();
    for (final s in _sheets) {
      if (s.name.toLowerCase() == n) return s;
    }
    return null;
  }

  /// A sheet name not yet used in this workbook (`Sheet2`, `Sheet3`, …).
  String freeName([String base = 'Sheet']) {
    var i = _sheets.length + 1;
    while (sheetNamed('$base$i') != null) {
      i++;
    }
    return '$base$i';
  }

  /// Adds a sheet. Throws [ArgumentError] when the name is taken or invalid.
  Sheet addSheet({String? name, int rowCount = 200, int columnCount = 26}) {
    final n = name ?? freeName();
    _checkName(n);
    final s = Sheet(name: n, rowCount: rowCount, columnCount: columnCount);
    _attach(s);
    _recalculate();
    notifyListeners();
    return s;
  }

  /// Adds an existing sheet (for example one built by a CSV import).
  void insertSheet(Sheet sheet, {int? index}) {
    _checkName(sheet.name);
    _attach(sheet, index);
    _recalculate();
    notifyListeners();
  }

  /// Removes a sheet. The last sheet cannot be removed.
  bool removeSheet(Sheet sheet) {
    if (_sheets.length <= 1 || !_sheets.remove(sheet)) return false;
    sheet.workbook = null;
    sheet.dispose();
    _recalculate();
    notifyListeners();
    return true;
  }

  /// Renames a sheet and updates formulas that reference it.
  void renameSheet(Sheet sheet, String newName) {
    final name = newName.trim();
    if (name == sheet.name) return;
    _checkName(name, except: sheet);
    final old = sheet.name;
    sheet.name = name;
    final oldRef = RegExp(
      "(?:'${RegExp.escape(old.replaceAll("'", "''"))}'|(?<![A-Za-z0-9_.])${RegExp.escape(old)})!",
      caseSensitive: false,
    );
    final replacement = '${SheetRefRewriter.quote(name)}!';
    for (final s in _sheets) {
      final updates = <CellCoordinate, String>{};
      for (final e in s.raw.getCellsInRange(s.fullRange)) {
        if (!e.value.isFormula) continue;
        final f = e.value.rawValue as String;
        if (!f.contains('!')) continue;
        final g = f.replaceAll(oldRef, replacement);
        if (g != f) updates[e.key] = g;
      }
      if (updates.isEmpty) continue;
      s.data.batchUpdateRaw((b) {
        updates.forEach((c, f) => b.setCell(c, CellValue.formula(f)));
      });
    }
    _recalculate();
    notifyListeners();
  }

  void moveSheet(int from, int to) {
    if (from < 0 || from >= _sheets.length) return;
    final s = _sheets.removeAt(from);
    _sheets.insert(to.clamp(0, _sheets.length), s);
    notifyListeners();
  }

  void _checkName(String name, {Sheet? except}) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Sheet name must not be empty.');
    }
    if (RegExp(r'[!\[\]:\\/?*]').hasMatch(name)) {
      throw ArgumentError(r'Sheet name must not contain ! [ ] : \ / ? *');
    }
    final other = sheetNamed(name);
    if (other != null && other != except) {
      throw ArgumentError('A sheet named "$name" already exists.');
    }
  }

  /// Drops every calculated value, without notifying anyone. Called at the
  /// moment of a write; listeners hear about it through [cellsChanged].
  void invalidate() {
    for (final s in _sheets) {
      s.data.clearCache();
    }
  }

  /// Called by a sheet when its cells changed.
  void cellsChanged(Sheet source) {
    if (_disposed) return;
    for (final s in _sheets) {
      // The source sheet already told its grid what changed.
      s.data.clearCache(notify: s != source);
    }
    notifyListeners();
  }

  void _recalculate() {
    for (final s in _sheets) {
      s.data.clearCache(notify: true);
    }
  }

  /// Recalculates every formula (after changing [locale] or the engine's
  /// functions).
  void recalculate() {
    _recalculate();
    notifyListeners();
  }

  // ── Calculation ────────────────────────────────────────────────────────

  /// Result of the formula stored at [coord], as a cell value.
  CellValue? calculate(Sheet sheet, CellCoordinate coord) =>
      _toCell(_formula(sheet, coord.row, coord.column));

  FormulaValue _formula(Sheet sheet, int row, int column) {
    final stored = sheet.raw.getCell(CellCoordinate(row, column));
    if (stored == null || !stored.isFormula) return _fromCell(stored);
    final key = '${identityHashCode(sheet)}:$row:$column';
    if (!_evaluating.add(key)) {
      return const FormulaValue.error(FormulaError.circular);
    }
    try {
      final text = stored.rawValue as String;
      final rw = _rewritten[text] ??= SheetRefRewriter.rewrite(text);
      return engine.evaluateString(
        rw.formula,
        _Context(this, sheet, A1.fromVector(column, row), rw.refs),
      );
    } catch (_) {
      return const FormulaValue.error(FormulaError.value);
    } finally {
      _evaluating.remove(key);
    }
  }

  /// Value of a cell as a formula operand. Formula cells are read through the
  /// sheet's cache unless they are being calculated right now (a cycle).
  FormulaValue _operand(Sheet sheet, int row, int column) {
    if (row < 0 || column < 0 || row >= sheet.rowCount || column >= sheet.columnCount) {
      return const EmptyValue();
    }
    final coord = CellCoordinate(row, column);
    final stored = sheet.raw.getCell(coord);
    if (stored == null) return const EmptyValue();
    if (!stored.isFormula) return _fromCell(stored);
    if (_evaluating.contains('${identityHashCode(sheet)}:$row:$column')) {
      return const FormulaValue.error(FormulaError.circular);
    }
    return _fromCell(sheet.data.getCell(coord));
  }

  FormulaValue _range(Sheet sheet, A1Range range) {
    final from = range.from.a1;
    final to = range.to.a1;
    if (from == null || to == null) {
      return const FormulaValue.error(FormulaError.ref);
    }
    final lastRow = to.row < sheet.rowCount ? to.row : sheet.rowCount - 1;
    final lastColumn =
        to.column < sheet.columnCount ? to.column : sheet.columnCount - 1;
    final rows = <List<FormulaValue>>[];
    for (var r = from.row; r <= lastRow; r++) {
      rows.add([
        for (var c = from.column; c <= lastColumn; c++) _operand(sheet, r, c),
      ]);
    }
    return FormulaValue.range(rows);
  }

  FormulaValue _sheetRef(SheetRef ref) {
    final target = sheetNamed(ref.sheet);
    if (target == null) return const FormulaValue.error(FormulaError.ref);
    try {
      if (ref.isRange) {
        final parts = ref.reference.split(':');
        final a = A1.parse(parts[0]);
        final b = A1.parse(parts[1]);
        final rows = <List<FormulaValue>>[];
        final r0 = a.row < b.row ? a.row : b.row;
        final r1 = a.row < b.row ? b.row : a.row;
        final c0 = a.column < b.column ? a.column : b.column;
        final c1 = a.column < b.column ? b.column : a.column;
        for (var r = r0; r <= r1 && r < target.rowCount; r++) {
          rows.add([
            for (var c = c0; c <= c1 && c < target.columnCount; c++)
              _operand(target, r, c),
          ]);
        }
        return FormulaValue.range(rows);
      }
      final a = A1.parse(ref.reference);
      return _operand(target, a.row, a.column);
    } catch (_) {
      return const FormulaValue.error(FormulaError.ref);
    }
  }

  static final _excelEpoch = DateTime.utc(1899, 12, 30);

  static FormulaValue _fromCell(CellValue? v) {
    if (v == null) return const EmptyValue();
    if (v.isNumber) return FormulaValue.number(v.asDouble);
    if (v.isText) return FormulaValue.text(v.rawValue as String);
    if (v.isBoolean) return FormulaValue.boolean(v.rawValue as bool);
    if (v.isDate) {
      final d = v.asDateTime;
      final utc = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
      return FormulaValue.number(
        utc.difference(_excelEpoch).inSeconds / Duration.secondsPerDay,
      );
    }
    if (v.isDuration) {
      return FormulaValue.number(
        v.asDuration.inMilliseconds / Duration.millisecondsPerDay,
      );
    }
    if (v.isError) {
      final code = v.rawValue as String;
      for (final e in FormulaError.values) {
        if (e.code == code) return FormulaValue.error(e);
      }
      return const FormulaValue.error(FormulaError.value);
    }
    return const EmptyValue();
  }

  static CellValue? _toCell(FormulaValue fv) => switch (fv) {
        NumberValue(value: final n) => n.isFinite
            ? CellValue.number(n)
            : CellValue.error(FormulaError.num.code),
        TextValue(value: final s) => CellValue.text(s),
        BooleanValue(value: final b) => CellValue.boolean(b),
        ErrorValue(error: final e) => CellValue.error(e.code),
        // A range or array result shows its first value, like a single cell
        // does in a spreadsheet without spilling.
        RangeValue(values: final v) =>
          v.isEmpty || v.first.isEmpty ? null : _toCell(v.first.first),
        FunctionValue() => CellValue.text(fv.toText()),
        EmptyValue() => CellValue.number(0),
        OmittedValue() => null,
      };

  @override
  void dispose() {
    _disposed = true;
    for (final s in _sheets) {
      s.dispose();
    }
    super.dispose();
  }
}

class _Context implements EvaluationContext {
  _Context(this._workbook, this._sheet, this.currentCell, this._refs);

  final Workbook _workbook;
  final Sheet _sheet;
  final Map<String, SheetRef> _refs;

  @override
  final A1 currentCell;

  @override
  String? get currentSheet => _sheet.name;

  @override
  bool get isCancelled => false;

  @override
  FormulaValue getCellValue(A1 cell) =>
      _workbook._operand(_sheet, cell.row, cell.column);

  @override
  FormulaValue getRangeValues(A1Range range) => _workbook._range(_sheet, range);

  @override
  FormulaFunction? getFunction(String name) =>
      _workbook.engine.functions.get(name);

  @override
  FormulaValue? getVariable(String name) {
    final ref = _refs[name];
    return ref == null ? null : _workbook._sheetRef(ref);
  }
}
