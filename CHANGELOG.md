## 0.1.0

First version.

- Workbook with several sheets; formulas across sheets (`=Sheet2!B4`,
  `=SUM('My data'!A1:A9)`); renaming a sheet updates references to it.
- Numbers and dates typed and displayed in the workbook's locale
  (`1234,5`, `12,5 %`, `1.234,50 €`, `20.11.2026.`); Croatian, German,
  French, US and British English built in.
- Fill colour, alignment, wrapping and number format for cells, whole rows or
  whole columns.
- Summary of the selection: sum, average, min, max, count.
- Column, line and pie charts from a selected range.
- CSV import and export with delimiter detection.
- Workbook saved to and loaded from JSON.
- `MojiSheetView`: toolbar, formula bar, grid, charts, summary, sheet tabs.
