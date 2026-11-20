import 'package:worksheet/worksheet.dart' show CellRange;

import 'workbook.dart';

enum SheetChartType { bar, line, pie }

/// A chart drawn from a range of a sheet.
///
/// The range is read as a table: with [firstColumnIsLabels] the first column
/// names the points, with [firstRowIsHeader] the first row names the series.
/// Every remaining column is one series (a pie uses the first series only).
class SheetChart {
  SheetChart({
    required this.type,
    required this.range,
    this.title = '',
    this.firstRowIsHeader = true,
    this.firstColumnIsLabels = true,
  });

  SheetChartType type;
  CellRange range;
  String title;
  bool firstRowIsHeader;
  bool firstColumnIsLabels;

  /// Reads the chart's numbers from [sheet] as they are calculated now.
  ChartData read(Sheet sheet) {
    final r0 = range.startRow + (firstRowIsHeader ? 1 : 0);
    final c0 = range.startColumn + (firstColumnIsLabels ? 1 : 0);
    final labels = <String>[];
    for (var r = r0; r <= range.endRow; r++) {
      labels.add(
        firstColumnIsLabels
            ? sheet.displayAt(r, range.startColumn)
            : '${r - r0 + 1}',
      );
    }
    final series = <ChartSeries>[];
    for (var c = c0; c <= range.endColumn; c++) {
      final values = <double?>[];
      for (var r = r0; r <= range.endRow; r++) {
        final v = sheet.valueAt(r, c);
        values.add(v != null && v.isNumber ? v.asDouble : null);
      }
      series.add(
        ChartSeries(
          firstRowIsHeader ? sheet.displayAt(range.startRow, c) : '',
          values,
        ),
      );
    }
    return ChartData(labels, series);
  }
}

class ChartSeries {
  const ChartSeries(this.name, this.values);
  final String name;

  /// One value per label; `null` where the cell holds no number.
  final List<double?> values;
}

class ChartData {
  const ChartData(this.labels, this.series);
  final List<String> labels;
  final List<ChartSeries> series;

  bool get isEmpty =>
      labels.isEmpty || series.every((s) => s.values.every((v) => v == null));
}
