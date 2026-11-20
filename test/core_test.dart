import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:moji_sheet/moji_sheet.dart';

void main() {
  group('SheetLocale.parseNumber', () {
    test('Croatian', () {
      const l = SheetLocale.hr;
      expect(l.parseNumber('1.234,50')!.value, 1234.5);
      expect(l.parseNumber('1234,5')!.value, 1234.5);
      expect(l.parseNumber('-0,25')!.value, -0.25);
      expect(l.parseNumber('12,5 %')!.value, closeTo(0.125, 1e-12));
      expect(l.parseNumber('12,5 %')!.format!.type, CellFormatType.percentage);
      expect(l.parseNumber('1.234,50 €')!.value, 1234.5);
      expect(l.parseNumber('1.234,50 €')!.format!.type, CellFormatType.currency);
      expect(l.parseNumber('42')!.value, 42);
      expect(l.parseNumber('42')!.format, isNull);
    });
    test('rejects what is not a number in this locale', () {
      const l = SheetLocale.hr;
      expect(l.parseNumber('1,234.50'), isNull);
      expect(l.parseNumber('20.11.2026.'), isNull);
      expect(l.parseNumber('20.11.'), isNull);
      expect(l.parseNumber('abc'), isNull);
      expect(l.parseNumber('12 34'), isNull);
      expect(l.parseNumber(''), isNull);
    });
    test('US English', () {
      const l = SheetLocale.enUs;
      expect(l.parseNumber('1,234.50')!.value, 1234.5);
      expect(l.parseNumber(r'$1,234.50')!.value, 1234.5);
      expect(l.parseNumber('42%')!.value, closeTo(0.42, 1e-12));
      expect(l.parseNumber('1.234,50'), isNull);
    });
    test('French groups by space', () {
      expect(SheetLocale.fr.parseNumber('1 234,50')!.value, 1234.5);
    });
    test('forCode', () {
      expect(SheetLocale.forCode('hr_HR'), SheetLocale.hr);
      expect(SheetLocale.forCode('en-GB'), SheetLocale.enGb);
      expect(SheetLocale.forCode('xx'), SheetLocale.enUs);
    });
  });

  group('Workbook', () {
    test('typed input is recognised and displayed in the locale', () {
      final wb = Workbook(locale: SheetLocale.hr);
      final s = wb.sheets.first;
      s.setInput(0, 0, '1234,5');
      s.setInput(1, 0, '20.11.2026.');
      s.setInput(2, 0, 'tekst');
      s.setInput(3, 0, '12,5 %');
      s.setInput(4, 0, '1.234,50 €');
      expect(s.valueAt(0, 0)!.asDouble, 1234.5);
      expect(s.displayAt(0, 0), '1234,5');
      expect(s.valueAt(1, 0)!.isDate, isTrue);
      expect(s.displayAt(1, 0), '20.11.2026.');
      expect(s.valueAt(2, 0)!.isText, isTrue);
      expect(s.displayAt(3, 0), '12,5%');
      expect(s.displayAt(4, 0), '1.234,50 €');
      wb.dispose();
    });

    test('the grid paints in the locale without being told the locale', () {
      final wb = Workbook(locale: SheetLocale.hr);
      final s = wb.sheets.first;
      s.setInput(0, 0, '12,5 %');
      s.setInput(1, 0, '1234,5');
      s.setInput(2, 0, '1.234,50 €');
      String painted(int row) {
        final c = CellCoordinate(row, 0);
        // Exactly what the grid's painter does: no locale argument.
        return s.data.getFormat(c)!.formatRich(s.data.getCell(c)!).text;
      }

      expect(painted(0), '12,5%');
      expect(painted(1), '1234,5');
      expect(painted(2), '1.234,50 €');
      // The stored format stays a plain one (it is what gets saved).
      expect(s.raw.getFormat(const CellCoordinate(0, 0)), isNot(isA<LocalizedCellFormat>()));
      wb.dispose();
    });

    test('text set through the grid data is localized too', () {
      final wb = Workbook(locale: SheetLocale.hr);
      final s = wb.sheets.first;
      s.data.setCell(const CellCoordinate(0, 0), const CellValue.text('1234,5'));
      s.data.batchUpdate((b) {
        b.setCell(const CellCoordinate(1, 0), const CellValue.text('7,25'));
      });
      expect(s.valueAt(0, 0)!.asDouble, 1234.5);
      expect(s.valueAt(1, 0)!.asDouble, 7.25);
      wb.dispose();
    });

    test('formulas: sum, average, min, max, count', () {
      final wb = Workbook();
      final s = wb.sheets.first;
      for (var i = 0; i < 4; i++) {
        s.setInput(i, 0, '${(i + 1) * 10}');
      }
      s.setInput(0, 1, '=SUM(A1:A4)');
      s.setInput(1, 1, '=AVERAGE(A1:A4)');
      s.setInput(2, 1, '=MIN(A1:A4)');
      s.setInput(3, 1, '=MAX(A1:A4)');
      s.setInput(4, 1, '=COUNT(A1:A4)');
      s.setInput(5, 1, '=B1*2+A1');
      expect(s.valueAt(0, 1)!.asDouble, 100);
      expect(s.valueAt(1, 1)!.asDouble, 25);
      expect(s.valueAt(2, 1)!.asDouble, 10);
      expect(s.valueAt(3, 1)!.asDouble, 40);
      expect(s.valueAt(4, 1)!.asDouble, 4);
      expect(s.valueAt(5, 1)!.asDouble, 210);
      // Results follow a change of their inputs.
      s.setInput(0, 0, '110');
      expect(s.valueAt(0, 1)!.asDouble, 200);
      expect(s.valueAt(5, 1)!.asDouble, 510);
      wb.dispose();
    });

    test('formulas across sheets', () {
      final wb = Workbook();
      final a = wb.sheets.first;
      final b = wb.addSheet(name: 'Data 2');
      b.setInput(0, 0, '5');
      b.setInput(1, 0, '7');
      a.setInput(0, 0, '100');
      a.setInput(0, 1, "='Data 2'!A1");
      a.setInput(1, 1, "=SUM('Data 2'!A1:A2)+A1");
      expect(a.valueAt(0, 1)!.asDouble, 5);
      expect(a.valueAt(1, 1)!.asDouble, 112);
      // A change on the other sheet reaches this one.
      b.setInput(1, 0, '70');
      expect(a.valueAt(1, 1)!.asDouble, 175);
      // Renaming keeps references working.
      wb.renameSheet(b, 'Podaci');
      expect((a.raw.getCell(const CellCoordinate(0, 1))!.rawValue as String),
          '=Podaci!A1');
      expect(a.valueAt(1, 1)!.asDouble, 175);
      // A missing sheet is a reference error, not a silent wrong value.
      a.setInput(2, 1, '=Nema!A1');
      expect(a.valueAt(2, 1)!.isError, isTrue);
      wb.dispose();
    });

    test('a sheet reference inside a text literal is left alone', () {
      final r = SheetRefRewriter.rewrite('="Sheet2!A1"&Sheet2!A1');
      expect(r.refs.length, 1);
      expect(r.formula.startsWith('="Sheet2!A1"&'), isTrue);
    });

    test('circular reference is an error, also across sheets', () {
      final wb = Workbook();
      final a = wb.sheets.first;
      final b = wb.addSheet(name: 'B');
      a.setInput(0, 0, '=B!A1+1');
      b.setInput(0, 0, '=Sheet1!A1+1');
      expect(a.valueAt(0, 0)!.isError, isTrue);
      a.setInput(1, 0, '=A2');
      expect(a.valueAt(1, 0)!.isError, isTrue);
      wb.dispose();
    });

    test('sheet names', () {
      final wb = Workbook();
      expect(() => wb.addSheet(name: 'Sheet1'), throwsArgumentError);
      expect(() => wb.addSheet(name: 'a!b'), throwsArgumentError);
      final s = wb.addSheet();
      expect(s.name, 'Sheet2');
      expect(wb.removeSheet(s), isTrue);
      expect(wb.removeSheet(wb.sheets.first), isFalse);
      wb.dispose();
    });
  });

  group('CSV', () {
    test('parse: quotes, embedded delimiters and line breaks, BOM', () {
      final rows = SheetCsv.parse(
        '﻿a;b;c\r\n"x;1";"he said ""hi""";"two\nlines"\r\n\r\n1;2;3',
      );
      expect(rows, [
        ['a', 'b', 'c'],
        ['x;1', 'he said "hi"', 'two\nlines'],
        ['1', '2', '3'],
      ]);
    });
    test('delimiter detection', () {
      expect(SheetCsv.detectDelimiter('a,b,c\n1,2,3'), ',');
      expect(SheetCsv.detectDelimiter('a;b;c\n1,5;2;3'), ';');
      expect(SheetCsv.detectDelimiter('a\tb\n1\t2'), '\t');
    });
    test('import types fields in the locale and does not plant formulas', () {
      final s = SheetCsv.toSheet(
        'Naziv;Iznos;Datum;Šifra\nKruh;1.234,50;20.11.2026.;00123\n=SUM(B2);2,5;;x',
        name: 'Uvoz',
        locale: SheetLocale.hr,
      );
      final wb = Workbook(locale: SheetLocale.hr, sheets: [s]);
      expect(s.valueAt(0, 0)!.isText, isTrue);
      expect(s.valueAt(1, 1)!.asDouble, 1234.5);
      expect(s.valueAt(1, 2)!.isDate, isTrue);
      expect(s.valueAt(1, 3)!.isText, isTrue);
      expect(s.valueAt(1, 3)!.rawValue, '00123');
      expect(s.raw.getCell(const CellCoordinate(2, 0))!.isFormula, isFalse);
      expect(s.valueAt(2, 1)!.asDouble, 2.5);
      wb.dispose();
    });
    test('export reads back to the same values', () {
      final wb = Workbook(locale: SheetLocale.hr);
      final s = wb.sheets.first;
      s.setInput(0, 0, 'Naziv; s točkom-zarezom');
      s.setInput(0, 1, '1234,5');
      s.setInput(1, 0, 'Drugi "red"');
      s.setInput(1, 1, '=B1*2');
      final csv = SheetCsv.fromSheet(s);
      final back = SheetCsv.toSheet(csv, name: 'Natrag', locale: SheetLocale.hr);
      final wb2 = Workbook(locale: SheetLocale.hr, sheets: [back]);
      expect(back.valueAt(0, 0)!.rawValue, 'Naziv; s točkom-zarezom');
      expect(back.valueAt(0, 1)!.asDouble, 1234.5);
      expect(back.valueAt(1, 0)!.rawValue, 'Drugi "red"');
      expect(back.valueAt(1, 1)!.asDouble, 2469);
      wb.dispose();
      wb2.dispose();
    });
  });

  group('JSON', () {
    test('round trip keeps values, formulas, formats, styles, sizes, charts', () {
      final wb = Workbook(locale: SheetLocale.hr);
      final a = wb.sheets.first;
      final b = wb.addSheet(name: 'Drugi list');
      a.setInput(0, 0, 'Artikl');
      a.setInput(1, 0, '12,5 %');
      a.setInput(2, 0, '20.11.2026.');
      a.setInput(3, 0, '=SUM(\'Drugi list\'!A1:A2)');
      a.setInput(4, 0, 'true');
      b.setInput(0, 0, '3');
      b.setInput(1, 0, '4');
      a.raw.setStyle(
        const CellCoordinate(0, 0),
        const CellStyle(
          backgroundColor: Color(0xFFFFE0B2),
          textAlignment: CellTextAlignment.center,
        ),
      );
      a.columnWidths[0] = 180;
      a.raw.mergeCells(const CellRange(6, 0, 6, 2));
      a.charts.add(
        SheetChart(
          type: SheetChartType.line,
          range: const CellRange(0, 0, 3, 1),
          title: 'Promet',
        ),
      );

      final json = WorkbookJson.encode(wb);
      final back = WorkbookJson.decode(json);
      final a2 = back.sheets.first;
      expect(back.locale, SheetLocale.hr);
      expect(back.sheets.map((s) => s.name), ['Sheet1', 'Drugi list']);
      expect(a2.valueAt(0, 0)!.rawValue, 'Artikl');
      expect(a2.displayAt(1, 0), '12,5%');
      expect(a2.displayAt(2, 0), '20.11.2026.');
      expect(a2.raw.getCell(const CellCoordinate(3, 0))!.isFormula, isTrue);
      expect(a2.valueAt(3, 0)!.asDouble, 7);
      expect(a2.valueAt(4, 0)!.rawValue, true);
      final st = a2.raw.getStyle(const CellCoordinate(0, 0))!;
      expect(st.backgroundColor, const Color(0xFFFFE0B2));
      expect(st.textAlignment, CellTextAlignment.center);
      expect(a2.columnWidths[0], 180);
      expect(a2.raw.mergedCells.regionCount, 1);
      expect(a2.charts.single.type, SheetChartType.line);
      expect(a2.charts.single.title, 'Promet');
      // Encoding the loaded workbook gives the same document.
      expect(WorkbookJson.encode(back), json);
      wb.dispose();
      back.dispose();
    });
    test('refuses foreign and newer documents', () {
      expect(() => WorkbookJson.decode('{"format":"x"}'), throwsFormatException);
      expect(
        () => WorkbookJson.decode('{"format":"moji_sheet","version":99}'),
        throwsFormatException,
      );
    });
  });

  test('chart data is read from calculated values', () {
    final wb = Workbook();
    final s = wb.sheets.first;
    s.setInput(0, 0, 'Month');
    s.setInput(0, 1, 'Sales');
    s.setInput(1, 0, 'Jan');
    s.setInput(1, 1, '10');
    s.setInput(2, 0, 'Feb');
    s.setInput(2, 1, '=B2*2');
    final d = SheetChart(
      type: SheetChartType.bar,
      range: const CellRange(0, 0, 2, 1),
    ).read(s);
    expect(d.labels, ['Jan', 'Feb']);
    expect(d.series.single.name, 'Sales');
    expect(d.series.single.values, [10, 20]);
    wb.dispose();
  });
}
