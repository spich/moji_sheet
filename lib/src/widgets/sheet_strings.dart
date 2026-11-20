/// Texts of the sheet's own interface. English by default; pass
/// [MojiSheetStrings.hr] or your own instance to [MojiSheetView].
class MojiSheetStrings {
  const MojiSheetStrings({
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.fill = 'Fill colour',
    this.noFill = 'No fill',
    this.scopeCells = 'Selected cells',
    this.scopeRows = 'Whole rows',
    this.scopeColumns = 'Whole columns',
    this.alignLeft = 'Align left',
    this.alignCenter = 'Centre',
    this.alignRight = 'Align right',
    this.wrap = 'Wrap text',
    this.format = 'Number format',
    this.formatAuto = 'Automatic',
    this.formatNumber = 'Number',
    this.formatThousands = 'Thousands separator',
    this.formatPercent = 'Percent',
    this.formatCurrency = 'Currency',
    this.formatDate = 'Date',
    this.formatDateTime = 'Date and time',
    this.formatText = 'Text',
    this.chart = 'Chart',
    this.chartBar = 'Column chart',
    this.chartLine = 'Line chart',
    this.chartPie = 'Pie chart',
    this.chartSelectFirst = 'Select the cells to chart first.',
    this.chartEmpty = 'No numbers in this range.',
    this.removeChart = 'Remove chart',
    this.importCsv = 'Import CSV',
    this.exportCsv = 'Export CSV',
    this.addSheet = 'Add sheet',
    this.rename = 'Rename',
    this.delete = 'Delete',
    this.sheetName = 'Sheet name',
    this.cancel = 'Cancel',
    this.ok = 'OK',
    this.deleteSheetQuestion = 'Delete this sheet and everything on it?',
    this.sum = 'Sum',
    this.average = 'Average',
    this.min = 'Min',
    this.max = 'Max',
    this.count = 'Count',
    this.newSheetBase = 'Sheet',
  });

  final String undo, redo, fill, noFill, scopeCells, scopeRows, scopeColumns;
  final String alignLeft, alignCenter, alignRight, wrap;
  final String format, formatAuto, formatNumber, formatThousands, formatPercent;
  final String formatCurrency, formatDate, formatDateTime, formatText;
  final String chart, chartBar, chartLine, chartPie, chartSelectFirst;
  final String chartEmpty, removeChart, importCsv, exportCsv;
  final String addSheet, rename, delete, sheetName, cancel, ok;
  final String deleteSheetQuestion, sum, average, min, max, count;

  /// Base of generated sheet names (`Sheet2`, `List2`).
  final String newSheetBase;

  static const en = MojiSheetStrings();

  static const hr = MojiSheetStrings(
    undo: 'Poništi',
    redo: 'Ponovi',
    fill: 'Boja ispune',
    noFill: 'Bez ispune',
    scopeCells: 'Odabrane ćelije',
    scopeRows: 'Cijeli retci',
    scopeColumns: 'Cijeli stupci',
    alignLeft: 'Poravnaj lijevo',
    alignCenter: 'Centriraj',
    alignRight: 'Poravnaj desno',
    wrap: 'Prelamanje teksta',
    format: 'Format broja',
    formatAuto: 'Automatski',
    formatNumber: 'Broj',
    formatThousands: 'Razdjelnik tisućica',
    formatPercent: 'Postotak',
    formatCurrency: 'Valuta',
    formatDate: 'Datum',
    formatDateTime: 'Datum i vrijeme',
    formatText: 'Tekst',
    chart: 'Grafikon',
    chartBar: 'Stupčasti grafikon',
    chartLine: 'Linijski grafikon',
    chartPie: 'Tortni grafikon',
    chartSelectFirst: 'Prvo odaberi ćelije za grafikon.',
    chartEmpty: 'U ovom rasponu nema brojeva.',
    removeChart: 'Ukloni grafikon',
    importCsv: 'Uvezi CSV',
    exportCsv: 'Izvezi CSV',
    addSheet: 'Dodaj list',
    rename: 'Preimenuj',
    delete: 'Obriši',
    sheetName: 'Naziv lista',
    cancel: 'Odustani',
    ok: 'U redu',
    deleteSheetQuestion: 'Obrisati ovaj list i sve na njemu?',
    sum: 'Zbroj',
    average: 'Prosjek',
    min: 'Min',
    max: 'Max',
    count: 'Broj',
    newSheetBase: 'List',
  );
}
