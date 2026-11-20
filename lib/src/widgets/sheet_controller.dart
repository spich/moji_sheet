import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:worksheet/worksheet.dart' hide FormulaFunction;

import '../io/csv.dart';
import '../io/workbook_json.dart';
import '../model/sheet_chart.dart';
import '../model/workbook.dart';

/// What a fill or format command applies to.
enum SheetScope {
  /// The selected cells.
  cells,

  /// Every cell of the selected rows.
  rows,

  /// Every cell of the selected columns.
  columns,
}

/// Aggregates of the selected cells, shown in the summary bar.
class SelectionSummary {
  const SelectionSummary({
    required this.cells,
    required this.numbers,
    required this.sum,
    required this.min,
    required this.max,
  });

  /// Selected cells that hold a value.
  final int cells;

  /// Of those, cells that hold a number.
  final int numbers;
  final double sum;
  final double? min;
  final double? max;

  double? get average => numbers == 0 ? null : sum / numbers;
}

/// Drives a [MojiSheetView]: which sheet is shown, what is selected, and the
/// commands the toolbar offers. Also usable without a view.
class MojiSheetController extends ChangeNotifier {
  MojiSheetController({Workbook? workbook}) : _workbook = workbook ?? Workbook() {
    _workbook.addListener(_onWorkbookChanged);
  }

  Workbook _workbook;
  Workbook get workbook => _workbook;

  int _active = 0;
  final Map<Sheet, _SheetState> _states = {};
  bool _disposed = false;

  /// Replaces the workbook (after loading a file). The old one is disposed.
  set workbook(Workbook value) {
    if (identical(value, _workbook)) return;
    _workbook.removeListener(_onWorkbookChanged);
    _disposeStates();
    _workbook.dispose();
    _workbook = value;
    _active = 0;
    _workbook.addListener(_onWorkbookChanged);
    notifyListeners();
  }

  void _onWorkbookChanged() {
    if (_disposed) return;
    final sheets = _workbook.sheets;
    _states.removeWhere((sheet, state) {
      if (sheets.contains(sheet)) return false;
      state.dispose();
      return true;
    });
    if (_active >= sheets.length) _active = sheets.length - 1;
    notifyListeners();
  }

  // ── Sheets ─────────────────────────────────────────────────────────────

  int get activeIndex => _active;
  Sheet get activeSheet => _workbook.sheets[_active];

  set activeIndex(int index) {
    if (index < 0 || index >= _workbook.sheets.length || index == _active) return;
    _active = index;
    notifyListeners();
  }

  Sheet addSheet({String? name}) {
    final s = _workbook.addSheet(name: name);
    _active = _workbook.sheets.indexOf(s);
    notifyListeners();
    return s;
  }

  bool removeSheet(Sheet sheet) => _workbook.removeSheet(sheet);

  void renameSheet(Sheet sheet, String name) =>
      _workbook.renameSheet(sheet, name);

  // ── Grid plumbing (used by the view) ───────────────────────────────────

  _SheetState _state(Sheet sheet) =>
      _states.putIfAbsent(sheet, () => _SheetState(this));

  /// The grid controller of [sheet] (selection, scrolling, zoom, undo).
  WorksheetController gridController(Sheet sheet) => _state(sheet).grid;

  EditController editController(Sheet sheet) => _state(sheet).edit;

  UndoManager undoManager(Sheet sheet) => _state(sheet).undo;

  // ── Selection ──────────────────────────────────────────────────────────

  /// The selected range on the active sheet.
  CellRange? get selection => gridController(activeSheet).selectedRange;

  /// The cell that has focus on the active sheet.
  CellCoordinate? get focusCell => gridController(activeSheet).focusCell;

  CellRange? _scoped(SheetScope scope) {
    final sel = selection;
    if (sel == null) return null;
    final s = activeSheet;
    return switch (scope) {
      SheetScope.cells => sel,
      SheetScope.rows =>
        CellRange(sel.startRow, 0, sel.endRow, s.columnCount - 1),
      SheetScope.columns =>
        CellRange(0, sel.startColumn, s.rowCount - 1, sel.endColumn),
    };
  }

  void _restyle(SheetScope scope, CellStyle Function(CellStyle? old) change) {
    final range = _scoped(scope);
    if (range == null) return;
    final s = activeSheet;
    final existing = {
      for (final e in s.raw.getStylesInRange(range)) e.key: e.value,
    };
    s.data.batchUpdateRaw((b) {
      for (var r = range.startRow; r <= range.endRow; r++) {
        for (var c = range.startColumn; c <= range.endColumn; c++) {
          final coord = CellCoordinate(r, c);
          final next = change(existing[coord]);
          b.setStyle(coord, _isEmpty(next) ? null : next);
        }
      }
    });
    notifyListeners();
  }

  static bool _isEmpty(CellStyle s) =>
      s.backgroundColor == null &&
      s.textAlignment == null &&
      s.verticalAlignment == null &&
      s.borders == null &&
      s.wrapText == null;

  static CellStyle _with(
    CellStyle? old, {
    Color? background,
    bool clearBackground = false,
    CellTextAlignment? alignment,
    bool clearAlignment = false,
    bool? wrap,
  }) =>
      CellStyle(
        backgroundColor:
            clearBackground ? null : (background ?? old?.backgroundColor),
        textAlignment: clearAlignment ? null : (alignment ?? old?.textAlignment),
        verticalAlignment: old?.verticalAlignment,
        borders: old?.borders,
        wrapText: wrap ?? old?.wrapText,
      );

  /// Fills the selection (or its rows or columns) with [color]; `null`
  /// removes the fill.
  void setBackground(Color? color, {SheetScope scope = SheetScope.cells}) =>
      _restyle(
        scope,
        (old) => _with(old, background: color, clearBackground: color == null),
      );

  /// Aligns text; `null` restores the default (numbers right, text left).
  void setAlignment(
    CellTextAlignment? alignment, {
    SheetScope scope = SheetScope.cells,
  }) =>
      _restyle(
        scope,
        (old) =>
            _with(old, alignment: alignment, clearAlignment: alignment == null),
      );

  void setWrap(bool wrap, {SheetScope scope = SheetScope.cells}) =>
      _restyle(scope, (old) => _with(old, wrap: wrap));

  /// Sets the number or date format; `null` restores automatic display.
  void setFormat(CellFormat? format, {SheetScope scope = SheetScope.cells}) {
    final range = _scoped(scope);
    if (range == null) return;
    activeSheet.data.batchUpdateRaw((b) {
      for (var r = range.startRow; r <= range.endRow; r++) {
        for (var c = range.startColumn; c <= range.endColumn; c++) {
          b.setFormat(CellCoordinate(r, c), format);
        }
      }
    });
    notifyListeners();
  }

  /// Deletes the values of the selected cells (formats and fills stay).
  void clearValues() {
    final range = selection;
    if (range == null) return;
    activeSheet.data.batchUpdateRaw((b) => b.clearValues(range));
    notifyListeners();
  }

  /// Count, sum, average, minimum and maximum of the selection.
  SelectionSummary? get summary {
    final range = selection;
    if (range == null) return null;
    final s = activeSheet;
    var cells = 0, numbers = 0;
    var sum = 0.0;
    double? min, max;
    // Only stored cells are visited, so selecting whole columns stays cheap.
    for (final e in s.raw.getCellsInRange(range)) {
      final v = e.value.isFormula ? s.data.getCell(e.key) : e.value;
      if (v == null) continue;
      cells++;
      if (!v.isNumber) continue;
      final n = v.asDouble;
      numbers++;
      sum += n;
      min = min == null || n < min ? n : min;
      max = max == null || n > max ? n : max;
    }
    return SelectionSummary(
      cells: cells,
      numbers: numbers,
      sum: sum,
      min: min,
      max: max,
    );
  }

  /// Raw content of the focused cell as the user would type it (a formula
  /// with its `=`, a number in the workbook's locale).
  String get focusInput {
    final c = focusCell;
    if (c == null) return '';
    final s = activeSheet;
    final v = s.raw.getCell(c);
    if (v == null) return '';
    if (v.isFormula) return v.rawValue as String;
    if (v.isNumber) return _workbook.locale.formatNumber(v.asDouble, maxDecimals: 10);
    if (v.isDate) return s.displayAt(c.row, c.column);
    return v.displayValue;
  }

  /// Types [input] into the focused cell.
  void setFocusInput(String input) {
    final c = focusCell;
    if (c == null) return;
    activeSheet.setInput(c.row, c.column, input);
    notifyListeners();
  }

  // ── Undo ───────────────────────────────────────────────────────────────

  bool get canUndo => undoManager(activeSheet).canUndo;
  bool get canRedo => undoManager(activeSheet).canRedo;
  void undo() => gridController(activeSheet).undo();
  void redo() => gridController(activeSheet).redo();

  // ── Charts ─────────────────────────────────────────────────────────────

  /// Adds a chart of the selection to the active sheet. Returns `null` when
  /// nothing is selected.
  SheetChart? addChart(SheetChartType type, {String title = ''}) {
    final range = selection;
    if (range == null) return null;
    final s = activeSheet;
    // The first column names the points only when it holds no numbers;
    // otherwise every column is a series. The same test decides whether the
    // first row is a header.
    bool numberAt(int r, int col) {
      final v = s.valueAt(r, col);
      return v != null && v.isNumber;
    }

    var hasLabels = range.endColumn > range.startColumn;
    if (hasLabels) {
      for (var r = range.startRow + 1; r <= range.endRow; r++) {
        if (numberAt(r, range.startColumn)) hasLabels = false;
      }
      if (range.endRow == range.startRow &&
          numberAt(range.startRow, range.startColumn)) {
        hasLabels = false;
      }
    }
    var header = range.endRow > range.startRow;
    if (header) {
      for (var col = range.startColumn + (hasLabels ? 1 : 0);
          col <= range.endColumn;
          col++) {
        if (numberAt(range.startRow, col)) header = false;
      }
    }
    final chart = SheetChart(
      type: type,
      range: range,
      title: title,
      firstRowIsHeader: header,
      firstColumnIsLabels: hasLabels,
    );
    s.charts.add(chart);
    notifyListeners();
    return chart;
  }

  void removeChart(SheetChart chart) {
    if (activeSheet.charts.remove(chart)) notifyListeners();
  }

  // ── Files ──────────────────────────────────────────────────────────────

  /// Imports CSV text as a new sheet and shows it.
  Sheet importCsv(String text, {String? name, String? delimiter}) {
    final sheet = SheetCsv.toSheet(
      text,
      name: _freeName(name),
      locale: _workbook.locale,
      delimiter: delimiter,
    );
    _workbook.insertSheet(sheet);
    _active = _workbook.sheets.indexOf(sheet);
    notifyListeners();
    return sheet;
  }

  String _freeName(String? wanted) {
    final base = (wanted ?? '').replaceAll(RegExp(r'[!\[\]:\\/?*]'), ' ').trim();
    if (base.isEmpty) return _workbook.freeName();
    var name = base;
    var i = 2;
    while (_workbook.sheetNamed(name) != null) {
      name = '$base $i';
      i++;
    }
    return name;
  }

  /// The active sheet as CSV.
  String exportCsv({String? delimiter, bool formatted = false}) =>
      SheetCsv.fromSheet(activeSheet, delimiter: delimiter, formatted: formatted);

  /// The whole workbook as JSON.
  String toJson({bool pretty = false}) =>
      WorkbookJson.encode(_workbook, pretty: pretty);

  /// Loads a workbook saved with [toJson].
  void loadJson(String json) => workbook = WorkbookJson.decode(json);

  /// Tells listeners that the selection moved (called by the view).
  void selectionChanged() {
    if (!_disposed) notifyListeners();
  }

  void _disposeStates() {
    for (final s in _states.values) {
      s.dispose();
    }
    _states.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _workbook.removeListener(_onWorkbookChanged);
    _disposeStates();
    _workbook.dispose();
    super.dispose();
  }
}

class _SheetState {
  _SheetState(MojiSheetController owner)
      : undo = UndoManager(maxDepth: 100),
        edit = EditController() {
    grid = WorksheetController(undoManager: undo);
    _listener = owner.selectionChanged;
    grid.selectionController.addListener(_listener);
    undo.addListener(_listener);
  }

  final UndoManager undo;
  final EditController edit;
  late final WorksheetController grid;
  late final VoidCallback _listener;

  void dispose() {
    grid.selectionController.removeListener(_listener);
    undo.removeListener(_listener);
    grid.dispose();
    edit.dispose();
    undo.dispose();
  }
}
