import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:worksheet/worksheet.dart' hide FormulaFunction;

import 'workbook.dart';

/// The cells of one sheet as the grid sees them.
///
/// Wraps the sheet's stored cells ([raw]) and
///  * returns the calculated value for formula cells (cached until anything
///    in the workbook changes),
///  * turns text typed in the workbook's locale into numbers (`1234,5`,
///    `12,5 %`, `1.234,50 €`),
///  * gives unformatted decimals and dates a locale format, so they are
///    displayed the way they were typed.
class SheetData extends WorksheetData {
  SheetData(this.sheet, this.raw) {
    _rawSub = raw.changes.listen(_onRawChange);
  }

  final Sheet sheet;

  /// Stored cells: formulas as text, no calculated values.
  final SparseWorksheetData raw;

  final Map<CellCoordinate, CellValue?> _cache = {};
  final StreamController<DataChangeEvent> _changes =
      StreamController<DataChangeEvent>.broadcast();
  late final StreamSubscription<DataChangeEvent> _rawSub;
  bool _disposed = false;

  Workbook? get _workbook => sheet.workbook;

  void _onRawChange(DataChangeEvent event) {
    if (_disposed) return;
    _changes.add(event);
    // A change anywhere may affect formulas anywhere, including other sheets.
    final wb = _workbook;
    if (wb != null) {
      wb.cellsChanged(sheet);
    } else {
      clearCache();
    }
  }

  /// Calculated values are dropped at once, in the same call that wrote —
  /// the change stream is delivered later, and a read in between must not
  /// see a stale result.
  void _touch() {
    final wb = _workbook;
    if (wb != null) {
      wb.invalidate();
    } else {
      _cache.clear();
    }
  }

  /// Drops calculated values. With [notify] the grid repaints.
  void clearCache({bool notify = false}) {
    _cache.clear();
    if (notify && !_disposed) _changes.add(DataChangeEvent.reset());
  }

  @override
  CellValue? getCell(CellCoordinate coord) {
    final value = raw.getCell(coord);
    if (value == null || !value.isFormula) return value;
    if (_cache.containsKey(coord)) return _cache[coord];
    final wb = _workbook;
    final result = wb == null
        ? const CellValue.error('#NAME?')
        : wb.calculate(sheet, coord);
    _cache[coord] = result;
    return result;
  }

  @override
  CellFormat? getFormat(CellCoordinate coord) {
    final locale = _workbook?.locale;
    final own = raw.getFormat(coord);
    if (own != null) return locale?.forDisplay(own) ?? own;
    if (locale == null) return null;
    final value = getCell(coord);
    if (value == null) return null;
    if (value.isNumber) {
      final f = locale.defaultNumberFormat(value.asDouble);
      return f == null ? null : locale.forDisplay(f);
    }
    if (value.isDate) {
      return locale.forDisplay(
        CellFormat(type: CellFormatType.date, formatCode: locale.dateFormat),
      );
    }
    return null;
  }

  /// Converts text written as a number in the workbook's locale.
  ({CellValue? value, CellFormat? format}) localized(CellValue? value) {
    final locale = _workbook?.locale;
    if (value == null || !value.isText || locale == null) {
      return (value: value, format: null);
    }
    final parsed = locale.parseNumber(value.rawValue as String);
    if (parsed == null) return (value: value, format: null);
    return (value: CellValue.number(parsed.value), format: parsed.format);
  }

  @override
  void setCell(CellCoordinate coord, CellValue? value) {
    final l = localized(value);
    _touch();
    if (l.format == null) {
      raw.setCell(coord, l.value);
    } else {
      raw.batchUpdate((b) {
        b.setCell(coord, l.value);
        b.setFormat(coord, l.format);
      });
    }
  }

  @override
  void batchUpdate(void Function(WorksheetDataBatch batch) updates) {
    _touch();
    raw.batchUpdate((b) => updates(_LocalizingBatch(this, b)));
  }

  /// Writes cells exactly as given (no locale conversion).
  void batchUpdateRaw(void Function(WorksheetDataBatch batch) updates) {
    _touch();
    raw.batchUpdate(updates);
  }

  @override
  Future<void> batchUpdateAsync(
    Future<void> Function(WorksheetDataBatch batch) updates,
  ) async {
    _touch();
    await raw.batchUpdateAsync((b) => updates(_LocalizingBatch(this, b)));
    _touch();
  }

  @override
  Stream<DataChangeEvent> get changes => _changes.stream;

  // ── Everything else is the stored sheet ────────────────────────────────

  @override
  int get rowCount => raw.rowCount;

  @override
  int get columnCount => raw.columnCount;

  @override
  bool hasValue(CellCoordinate coord) => raw.hasValue(coord);

  @override
  CellStyle? getStyle(CellCoordinate coord) => raw.getStyle(coord);

  @override
  void setStyle(CellCoordinate coord, CellStyle? style) =>
      raw.setStyle(coord, style);

  @override
  void setFormat(CellCoordinate coord, CellFormat? format) =>
      raw.setFormat(coord, format);

  @override
  List<TextSpan>? getRichText(CellCoordinate coord) => raw.getRichText(coord);

  @override
  void setRichText(CellCoordinate coord, List<TextSpan>? richText) =>
      raw.setRichText(coord, richText);

  @override
  Iterable<MapEntry<CellCoordinate, CellValue>> getCellsInRange(
    CellRange range,
  ) =>
      raw.getCellsInRange(range);

  @override
  Iterable<MapEntry<CellCoordinate, List<TextSpan>>> getRichTextInRange(
    CellRange range,
  ) =>
      raw.getRichTextInRange(range);

  @override
  Iterable<MapEntry<CellCoordinate, CellStyle>> getStylesInRange(
    CellRange range,
  ) =>
      raw.getStylesInRange(range);

  @override
  Iterable<MapEntry<CellCoordinate, CellFormat>> getFormatsInRange(
    CellRange range,
  ) =>
      raw.getFormatsInRange(range);

  @override
  void clearRange(CellRange range) {
    _touch();
    raw.clearRange(range);
  }

  @override
  void clearRichTextInRange(CellRange range) =>
      raw.clearRichTextInRange(range);

  @override
  CellRange? smartFill(
    CellRange range,
    CellCoordinate destination, [
    Cell? Function(CellCoordinate coord, Cell? sourceCell)? valueGenerator,
  ]) {
    _touch();
    return raw.smartFill(range, destination, valueGenerator);
  }

  @override
  void fillRange(
    CellCoordinate source,
    CellRange range, [
    Cell? Function(CellCoordinate coord, Cell? sourceCell)? valueGenerator,
  ]) {
    _touch();
    raw.fillRange(source, range, valueGenerator);
  }

  @override
  MergedCellRegistry get mergedCells => raw.mergedCells;

  @override
  void mergeCells(CellRange range) => raw.mergeCells(range);

  @override
  void unmergeCells(CellCoordinate cell) => raw.unmergeCells(cell);

  @override
  void unmergeCellsInRange(CellRange range) => raw.unmergeCellsInRange(range);

  @override
  void moveMerges(CellRange source, CellCoordinate destination) =>
      raw.moveMerges(source, destination);

  @override
  void replicateMerges({
    required CellRange sourceRange,
    required CellRange targetRange,
    required bool vertical,
  }) =>
      raw.replicateMerges(
        sourceRange: sourceRange,
        targetRange: targetRange,
        vertical: vertical,
      );

  @override
  int? findNextPopulatedRow(int column, int fromRow) =>
      raw.findNextPopulatedRow(column, fromRow);

  @override
  int? findPrevPopulatedRow(int column, int fromRow) =>
      raw.findPrevPopulatedRow(column, fromRow);

  @override
  int? findNextPopulatedColumn(int row, int fromColumn) =>
      raw.findNextPopulatedColumn(row, fromColumn);

  @override
  int? findPrevPopulatedColumn(int row, int fromColumn) =>
      raw.findPrevPopulatedColumn(row, fromColumn);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _rawSub.cancel();
    _changes.close();
    _cache.clear();
    raw.dispose();
  }
}

/// A batch that applies the same locale conversion as [SheetData.setCell].
class _LocalizingBatch implements WorksheetDataBatch {
  _LocalizingBatch(this._data, this._inner);

  final SheetData _data;
  final WorksheetDataBatch _inner;

  @override
  void setCell(CellCoordinate coord, CellValue? value) {
    final l = _data.localized(value);
    _inner.setCell(coord, l.value);
    if (l.format != null) _inner.setFormat(coord, l.format);
  }

  @override
  void setStyle(CellCoordinate coord, CellStyle? style) =>
      _inner.setStyle(coord, style);

  @override
  void setFormat(CellCoordinate coord, CellFormat? format) =>
      _inner.setFormat(coord, format);

  @override
  void setRichText(CellCoordinate coord, List<TextSpan>? richText) =>
      _inner.setRichText(coord, richText);

  @override
  void clearRange(CellRange range) => _inner.clearRange(range);

  @override
  void fillRangeWithCell(CellRange range, Cell? value) =>
      _inner.fillRangeWithCell(range, value);

  @override
  void clearValues(CellRange range) => _inner.clearValues(range);

  @override
  void clearStyles(CellRange range) => _inner.clearStyles(range);

  @override
  void clearFormats(CellRange range) => _inner.clearFormats(range);

  @override
  void copyRange(CellRange source, CellCoordinate destination) =>
      _inner.copyRange(source, destination);
}
