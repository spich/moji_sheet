import 'dart:ui' show Color;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moji_sheet/moji_sheet.dart';

MojiSheetController _filled() {
  final c = MojiSheetController(workbook: Workbook(locale: SheetLocale.hr));
  final s = c.activeSheet;
  const rows = [
    ['Mjesec', 'Usluge', 'Proizvodi'],
    ['Siječanj', '100', '10,5'],
    ['Veljača', '200', '20'],
    ['Ožujak', '=B2+B3', 'x'],
  ];
  for (var r = 0; r < rows.length; r++) {
    for (var col = 0; col < rows[r].length; col++) {
      s.setInput(r, col, rows[r][col]);
    }
  }
  return c;
}

void main() {
  test('summary of the selection counts formula results', () {
    final c = _filled();
    c.gridController(c.activeSheet).selectRange(const CellRange(1, 1, 3, 2));
    final s = c.summary!;
    expect(s.cells, 6);
    expect(s.numbers, 5);
    expect(s.sum, closeTo(630.5, 1e-9));
    expect(s.min, 10.5);
    expect(s.max, 300);
    expect(s.average, closeTo(126.1, 1e-9));
    c.dispose();
  });

  test('fill applies to cells, whole rows or whole columns', () {
    final c = _filled();
    final sheet = c.activeSheet;
    final grid = c.gridController(sheet);
    const red = Color(0xFFFFCDD2);

    grid.selectRange(const CellRange(1, 1, 1, 1));
    c.setBackground(red);
    expect(sheet.raw.getStyle(const CellCoordinate(1, 1))!.backgroundColor, red);
    expect(sheet.raw.getStyle(const CellCoordinate(1, 2)), isNull);

    c.setBackground(red, scope: SheetScope.rows);
    expect(sheet.raw.getStyle(const CellCoordinate(1, 0))!.backgroundColor, red);
    expect(
      sheet.raw.getStyle(CellCoordinate(1, sheet.columnCount - 1))!.backgroundColor,
      red,
    );
    expect(sheet.raw.getStyle(const CellCoordinate(2, 0)), isNull);

    c.setBackground(null, scope: SheetScope.rows);
    expect(sheet.raw.getStyle(const CellCoordinate(1, 0)), isNull);

    c.setBackground(red, scope: SheetScope.columns);
    expect(sheet.raw.getStyle(const CellCoordinate(0, 1))!.backgroundColor, red);
    expect(
      sheet.raw.getStyle(CellCoordinate(sheet.rowCount - 1, 1))!.backgroundColor,
      red,
    );
    // Alignment keeps the fill.
    grid.selectRange(const CellRange(0, 1, 0, 1));
    c.setAlignment(CellTextAlignment.center);
    final st = sheet.raw.getStyle(const CellCoordinate(0, 1))!;
    expect(st.backgroundColor, red);
    expect(st.textAlignment, CellTextAlignment.center);
    c.dispose();
  });

  test('chart from a selection recognises header and label column', () {
    final c = _filled();
    final grid = c.gridController(c.activeSheet);
    grid.selectRange(const CellRange(0, 0, 2, 2));
    final withLabels = c.addChart(SheetChartType.bar)!;
    expect(withLabels.firstRowIsHeader, isTrue);
    expect(withLabels.firstColumnIsLabels, isTrue);
    expect(withLabels.read(c.activeSheet).labels, ['Siječanj', 'Veljača']);

    // Numbers only: every column is a series, no header.
    grid.selectRange(const CellRange(1, 1, 2, 2));
    final numbersOnly = c.addChart(SheetChartType.line)!;
    expect(numbersOnly.firstRowIsHeader, isFalse);
    expect(numbersOnly.firstColumnIsLabels, isFalse);
    expect(numbersOnly.read(c.activeSheet).series.length, 2);
    c.dispose();
  });

  test('CSV import adds a sheet; JSON reload keeps the workbook', () {
    final c = _filled();
    final imported = c.importCsv('a;b\n1,5;2', name: 'Promet/2026');
    expect(imported.name, 'Promet 2026');
    expect(c.activeSheet, imported);
    expect(imported.valueAt(1, 0)!.asDouble, 1.5);
    c.importCsv('x;y\n1;2', name: 'Promet 2026');
    expect(c.workbook.sheets.last.name, 'Promet 2026 2');

    c.loadJson(c.toJson());
    expect(c.workbook.sheets.length, 3);
    expect(c.workbook.sheets.first.valueAt(3, 1)!.asDouble, 300);
    expect(c.exportCsv().isNotEmpty, isTrue);
    c.dispose();
  });

  testWidgets('view shows the sheet, switches tabs and adds a sheet', (tester) async {
    final c = _filled();
    c.workbook.addSheet(name: 'Drugi');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MojiSheetView(controller: c, strings: MojiSheetStrings.hr),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sheet1'), findsOneWidget);
    expect(find.text('Drugi'), findsOneWidget);

    await tester.tap(find.text('Drugi'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.activeSheet.name, 'Drugi');

    await tester.tap(find.byTooltip('Dodaj list'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.workbook.sheets.length, 3);
    expect(c.activeSheet.name, 'List3');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
