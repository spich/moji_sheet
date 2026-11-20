# moji_sheet

A small spreadsheet for Flutter — sheets, formulas, locale-aware numbers and
dates, cell colours, charts, CSV and JSON. Works on Android, iOS and the web
(including WebAssembly builds).

It is a thin, opinionated layer over three packages that do the heavy lifting:
[`worksheet`](https://pub.dev/packages/worksheet) (the grid),
[`worksheet_formula`](https://pub.dev/packages/worksheet_formula) (formulas)
and [`fl_chart`](https://pub.dev/packages/fl_chart) (charts). What it adds is
what an app needs to ship a usable sheet: several sheets calculated together,
input in the user's own number and date format, a toolbar, saving and loading.

## What you get

- **Sheets.** A workbook holds any number of sheets. Formulas reference other
  sheets (`=Summary!B2`, `=SUM('My data'!A1:A9)`), and renaming a sheet
  updates the formulas that point at it.
- **Formulas.** Around 400 spreadsheet functions (`SUM`, `AVERAGE`, `MIN`,
  `MAX`, `COUNT`, `IF`, `VLOOKUP`…), recalculated when their inputs change,
  with circular references reported as errors.
- **Locale-aware input and display.** In a Croatian workbook `1234,5`,
  `12,5 %`, `1.234,50 €` and `20.11.2026.` are recognised as a number, a
  percentage, a currency amount and a date, and are shown the same way.
  Built in: Croatian, German, French, US and British English; others are one
  `SheetLocale` away.
- **Formatting.** Fill colour, alignment, text wrapping and number format, for
  the selected cells, their whole rows or their whole columns.
- **Selection summary.** Sum, average, minimum, maximum and count of the
  selected cells.
- **Charts.** Column, line and pie charts drawn from a selected range.
- **CSV.** Import with delimiter detection and typed fields; export that reads
  back to the same values.
- **JSON.** The whole workbook — values, formulas, formats, fills, merged
  cells, column widths, charts — saved to and loaded from one document.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:moji_sheet/moji_sheet.dart';

class SheetPage extends StatefulWidget {
  const SheetPage({super.key});
  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  final controller = MojiSheetController(
    workbook: Workbook(locale: SheetLocale.hr),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: MojiSheetView(
            controller: controller,
            strings: MojiSheetStrings.hr, // English by default
          ),
        ),
      );
}
```

### Filling a sheet from code

```dart
final sheet = controller.activeSheet;
sheet.setInput(0, 0, 'Month');       // text
sheet.setInput(1, 1, '1.250,00');    // a number in the workbook's locale
sheet.setInput(5, 1, '=SUM(B2:B5)'); // a formula
print(sheet.valueAt(5, 1));          // calculated value
print(sheet.displayAt(5, 1));        // as shown in the grid
```

### Saving and loading

```dart
final json = controller.toJson();   // store it wherever your app stores data
controller.loadJson(json);
```

### CSV

The view never touches files. Give it two callbacks and the toolbar shows the
import and export buttons:

```dart
MojiSheetView(
  controller: controller,
  onImportCsv: () async {
    final text = await pickAndReadCsvFile(); // your file picker
    return text == null ? null : (text: text, name: 'Import');
  },
  onExportCsv: (csv, sheetName) => saveOrShare(csv, '$sheetName.csv'),
)
```

Without the view: `controller.importCsv(text)` and `controller.exportCsv()`,
or `SheetCsv.toSheet` / `SheetCsv.fromSheet` directly.

A field that starts with `=` is imported as text, not as a formula — a CSV
from elsewhere should not be able to plant formulas in your workbook.

### Without the widget

`Workbook`, `Sheet`, `SheetCsv` and `WorkbookJson` do not need a widget tree,
so the same code can fill, calculate and export a workbook in a test or a
background task.

## Limits of this version

- Formulas reference cells and ranges (`A1`, `B2:C10`, `Sheet2!A1`); whole
  columns or rows (`A:A`, `3:3`) are not supported.
- A formula that returns an array shows its first value; arrays do not spill
  into neighbouring cells.
- Any change recalculates every formula that is displayed. That is simple and
  correct, and fast for sheets of ordinary size; it is not built for
  hundreds of thousands of formulas.
- Cell borders, and rich text inside a cell, are not saved to JSON.
- Fill, alignment and format commands of the toolbar are not on the undo
  stack; editing cell values is.
- No XLSX import or export.

## Credits

The grid is [`worksheet`](https://pub.dev/packages/worksheet) and the formula
engine is [`worksheet_formula`](https://pub.dev/packages/worksheet_formula),
both by hornmicro.com; charts are drawn with
[`fl_chart`](https://pub.dev/packages/fl_chart). All three are MIT-licensed.

## License

MIT — see [LICENSE](LICENSE).
