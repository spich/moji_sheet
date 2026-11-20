import 'dart:async';

import 'package:flutter/material.dart';
import 'package:worksheet/worksheet.dart' hide FormulaFunction;

import '../model/sheet_chart.dart';
import '../model/workbook.dart';
import 'sheet_chart_view.dart';
import 'sheet_controller.dart';
import 'sheet_strings.dart';

/// Colours offered by the fill button.
const List<Color> sheetFillPalette = [
  Color(0xFFFFF2CC), Color(0xFFFFE0B2), Color(0xFFFFCDD2), Color(0xFFF8BBD0),
  Color(0xFFE1BEE7), Color(0xFFD1C4E9), Color(0xFFBBDEFB), Color(0xFFB3E5FC),
  Color(0xFFB2DFDB), Color(0xFFC8E6C9), Color(0xFFDCEDC8), Color(0xFFF0F4C3),
  Color(0xFFFFD54F), Color(0xFFFF8A65), Color(0xFFE57373), Color(0xFF64B5F6),
  Color(0xFF81C784), Color(0xFFE0E0E0), Color(0xFFBDBDBD), Color(0xFFFFFFFF),
];

/// A complete spreadsheet: toolbar, formula bar, grid, charts, summary of the
/// selection and sheet tabs.
///
/// ```dart
/// final controller = MojiSheetController(
///   workbook: Workbook(locale: SheetLocale.hr),
/// );
/// …
/// MojiSheetView(controller: controller, strings: MojiSheetStrings.hr)
/// ```
///
/// The view never touches files. To offer CSV import and export, pass
/// [onImportCsv] (return the file's text) and [onExportCsv] (save the text).
class MojiSheetView extends StatefulWidget {
  const MojiSheetView({
    super.key,
    required this.controller,
    this.strings = MojiSheetStrings.en,
    this.readOnly = false,
    this.showToolbar = true,
    this.showFormulaBar = true,
    this.showSummary = true,
    this.showSheetTabs = true,
    this.onImportCsv,
    this.onExportCsv,
    this.toolbarActions = const [],
    this.chartsHeight = 220,
  });

  final MojiSheetController controller;
  final MojiSheetStrings strings;

  /// Shows the workbook without letting it be changed.
  final bool readOnly;
  final bool showToolbar;
  final bool showFormulaBar;
  final bool showSummary;
  final bool showSheetTabs;

  /// Lets the user pick a CSV file; return its text and, optionally, a name
  /// for the new sheet. Return `null` when the user cancelled. The toolbar
  /// shows the import button only when this is set.
  final Future<({String text, String? name})?> Function()? onImportCsv;

  /// Receives the active sheet as CSV text to save or share. The toolbar
  /// shows the export button only when this is set.
  final void Function(String csv, String sheetName)? onExportCsv;

  /// Extra buttons at the end of the toolbar (save, share…).
  final List<Widget> toolbarActions;

  /// Height of the strip that shows the active sheet's charts.
  final double chartsHeight;

  @override
  State<MojiSheetView> createState() => _MojiSheetViewState();
}

class _MojiSheetViewState extends State<MojiSheetView> {
  final _formulaText = TextEditingController();
  final _formulaFocus = FocusNode();
  SheetScope _scope = SheetScope.cells;

  MojiSheetController get c => widget.controller;
  MojiSheetStrings get t => widget.strings;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
  }

  @override
  void didUpdateWidget(MojiSheetView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _formulaText.dispose();
    _formulaFocus.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    // The formula bar follows the focused cell unless it is being typed in.
    if (!_formulaFocus.hasFocus) {
      final text = c.focusInput;
      if (_formulaText.text != text) _formulaText.text = text;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sheet = c.activeSheet;
    return Column(
      children: [
        if (widget.showToolbar && !widget.readOnly) _toolbar(context),
        if (widget.showFormulaBar) _formulaBar(context, sheet),
        Expanded(child: _grid(context, sheet)),
        if (sheet.charts.isNotEmpty) _charts(context, sheet),
        if (widget.showSummary) _summary(context),
        if (widget.showSheetTabs) _tabs(context),
      ],
    );
  }

  // ── Grid ───────────────────────────────────────────────────────────────

  Widget _grid(BuildContext context, Sheet sheet) {
    final locale = c.workbook.locale;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final grid = c.gridController(sheet);
    return WorksheetTheme(
      data: dark
          ? WorksheetThemeData.darkTheme
          : WorksheetThemeData.defaultTheme,
      child: Worksheet(
        // One grid per sheet: switching sheets must not carry over scroll
        // position, selection or an open editor.
        key: ObjectKey(sheet),
        data: sheet.data,
        rawData: sheet.raw,
        controller: grid,
        editController: widget.readOnly ? null : c.editController(sheet),
        rowCount: sheet.rowCount,
        columnCount: sheet.columnCount,
        readOnly: widget.readOnly,
        formatLocale: locale.format,
        dateParser: AnyDate(
          info: DateParserInfo(dayFirst: locale.format.dayFirst),
        ),
        customColumnWidths: sheet.columnWidths,
        customRowHeights: sheet.rowHeights,
        onResizeColumn: (column, _) => _rememberSize(sheet, grid, column: column),
        onResizeRow: (row, _) => _rememberSize(sheet, grid, row: row),
      ),
    );
  }

  /// The grid resizes on its own; the new size is read back so that it is
  /// saved with the workbook.
  void _rememberSize(
    Sheet sheet,
    WorksheetController grid, {
    int? column,
    int? row,
  }) {
    scheduleMicrotask(() {
      final solver = grid.layoutSolver;
      if (solver == null) return;
      if (column != null) {
        sheet.columnWidths[column] = solver.getColumnWidth(column);
      }
      if (row != null) sheet.rowHeights[row] = solver.getRowHeight(row);
    });
  }

  // ── Formula bar ────────────────────────────────────────────────────────

  Widget _formulaBar(BuildContext context, Sheet sheet) {
    final theme = Theme.of(context);
    final focus = c.focusCell;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              focus?.toNotation() ?? '',
              style: theme.textTheme.labelLarge,
            ),
          ),
          const VerticalDivider(width: 12, indent: 8, endIndent: 8),
          Expanded(
            child: TextField(
              controller: _formulaText,
              focusNode: _formulaFocus,
              enabled: !widget.readOnly && focus != null,
              style: theme.textTheme.bodyMedium,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (text) {
                c.setFocusInput(text);
                _formulaFocus.unfocus();
              },
              onTapOutside: (_) {
                if (!_formulaFocus.hasFocus) return;
                // Leaving the bar keeps what was typed, like leaving a cell.
                if (_formulaText.text != c.focusInput) {
                  c.setFocusInput(_formulaText.text);
                }
                _formulaFocus.unfocus();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = c.selection != null;
    Widget button(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          button(Icons.undo, t.undo, c.canUndo ? c.undo : null),
          button(Icons.redo, t.redo, c.canRedo ? c.redo : null),
          const VerticalDivider(width: 8, indent: 10, endIndent: 10),
          _fillButton(context, hasSelection),
          _scopeButton(context),
          const VerticalDivider(width: 8, indent: 10, endIndent: 10),
          button(
            Icons.format_align_left,
            t.alignLeft,
            hasSelection
                ? () => c.setAlignment(CellTextAlignment.left, scope: _scope)
                : null,
          ),
          button(
            Icons.format_align_center,
            t.alignCenter,
            hasSelection
                ? () => c.setAlignment(CellTextAlignment.center, scope: _scope)
                : null,
          ),
          button(
            Icons.format_align_right,
            t.alignRight,
            hasSelection
                ? () => c.setAlignment(CellTextAlignment.right, scope: _scope)
                : null,
          ),
          button(
            Icons.wrap_text,
            t.wrap,
            hasSelection ? () => c.setWrap(true, scope: _scope) : null,
          ),
          _formatButton(context, hasSelection),
          const VerticalDivider(width: 8, indent: 10, endIndent: 10),
          _chartButton(context),
          if (widget.onImportCsv != null)
            button(Icons.upload_file_outlined, t.importCsv, _import),
          if (widget.onExportCsv != null)
            button(
              Icons.download_outlined,
              t.exportCsv,
              () => widget.onExportCsv!(c.exportCsv(), c.activeSheet.name),
            ),
          ...widget.toolbarActions,
        ],
      ),
    );
  }

  Future<void> _import() async {
    final picked = await widget.onImportCsv!();
    if (picked == null || !mounted) return;
    c.importCsv(picked.text, name: picked.name);
  }

  Widget _fillButton(BuildContext context, bool enabled) =>
      PopupMenuButton<int>(
        tooltip: t.fill,
        enabled: enabled,
        icon: const Icon(Icons.format_color_fill, size: 20),
        itemBuilder: (_) => [
          PopupMenuItem<int>(
            enabled: false,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 220,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final color in sheetFillPalette)
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        c.setBackground(color, scope: _scope);
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(color: Colors.black26),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          PopupMenuItem<int>(
            value: 0,
            child: Row(
              children: [
                const Icon(Icons.format_color_reset, size: 18),
                const SizedBox(width: 8),
                Text(t.noFill),
              ],
            ),
          ),
        ],
        onSelected: (_) => c.setBackground(null, scope: _scope),
      );

  Widget _scopeButton(BuildContext context) => PopupMenuButton<SheetScope>(
        tooltip: switch (_scope) {
          SheetScope.cells => t.scopeCells,
          SheetScope.rows => t.scopeRows,
          SheetScope.columns => t.scopeColumns,
        },
        icon: Icon(
          switch (_scope) {
            SheetScope.cells => Icons.grid_on,
            SheetScope.rows => Icons.table_rows_outlined,
            SheetScope.columns => Icons.view_column_outlined,
          },
          size: 20,
        ),
        initialValue: _scope,
        onSelected: (s) => setState(() => _scope = s),
        itemBuilder: (_) => [
          PopupMenuItem(value: SheetScope.cells, child: Text(t.scopeCells)),
          PopupMenuItem(value: SheetScope.rows, child: Text(t.scopeRows)),
          PopupMenuItem(value: SheetScope.columns, child: Text(t.scopeColumns)),
        ],
      );

  Widget _formatButton(BuildContext context, bool enabled) {
    final locale = c.workbook.locale;
    final currency = locale.format.currencySymbol;
    final formats = <(String, CellFormat?)>[
      (t.formatAuto, null),
      (t.formatNumber, CellFormat.decimal),
      (t.formatThousands, CellFormat.number),
      (t.formatPercent, CellFormat.percentageDecimal),
      (
        t.formatCurrency,
        CellFormat(
          type: CellFormatType.currency,
          formatCode: locale.format.decimalSeparator == ','
              ? '#,##0.00 "$currency"'
              : '"$currency"#,##0.00',
        ),
      ),
      (
        t.formatDate,
        CellFormat(type: CellFormatType.date, formatCode: locale.dateFormat),
      ),
      (
        t.formatDateTime,
        CellFormat(
          type: CellFormatType.date,
          formatCode: '${locale.dateFormat} hh:mm',
        ),
      ),
      (t.formatText, CellFormat.text),
    ];
    return PopupMenuButton<int>(
      tooltip: t.format,
      enabled: enabled,
      icon: const Icon(Icons.pin_outlined, size: 20),
      onSelected: (i) => c.setFormat(formats[i].$2, scope: _scope),
      itemBuilder: (_) => [
        for (var i = 0; i < formats.length; i++)
          PopupMenuItem(value: i, child: Text(formats[i].$1)),
      ],
    );
  }

  Widget _chartButton(BuildContext context) => PopupMenuButton<SheetChartType>(
        tooltip: t.chart,
        icon: const Icon(Icons.insert_chart_outlined, size: 20),
        onSelected: (type) {
          if (c.addChart(type) == null) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(t.chartSelectFirst)),
            );
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: SheetChartType.bar, child: Text(t.chartBar)),
          PopupMenuItem(value: SheetChartType.line, child: Text(t.chartLine)),
          PopupMenuItem(value: SheetChartType.pie, child: Text(t.chartPie)),
        ],
      );

  // ── Charts ─────────────────────────────────────────────────────────────

  Widget _charts(BuildContext context, Sheet sheet) {
    final theme = Theme.of(context);
    return Container(
      height: widget.chartsHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        children: [
          for (final chart in sheet.charts)
            Container(
              width: 340,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 18, right: 4),
                    child: SheetChartView(
                      chart: chart,
                      sheet: sheet,
                      emptyText: t.chartEmpty,
                    ),
                  ),
                  if (!widget.readOnly)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: () => c.removeChart(chart),
                        borderRadius: BorderRadius.circular(12),
                        child: Tooltip(
                          message: t.removeChart,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 16),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Summary ────────────────────────────────────────────────────────────

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final s = c.summary;
    final locale = c.workbook.locale;
    String n(double? v) => v == null ? '–' : locale.formatNumber(v, maxDecimals: 4);
    final parts = <String>[
      if (s != null && s.numbers > 1) ...[
        '${t.sum}: ${n(s.sum)}',
        '${t.average}: ${n(s.average)}',
        '${t.min}: ${n(s.min)}',
        '${t.max}: ${n(s.max)}',
      ],
      if (s != null && s.cells > 1) '${t.count}: ${s.cells}',
    ];
    return Container(
      height: 26,
      width: double.infinity,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Text(parts.join('   '), style: theme.textTheme.bodySmall),
      ),
    );
  }

  // ── Sheet tabs ─────────────────────────────────────────────────────────

  Widget _tabs(BuildContext context) {
    final theme = Theme.of(context);
    final sheets = c.workbook.sheets;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: t.addSheet,
              visualDensity: VisualDensity.compact,
              onPressed: () => c.addSheet(
                name: c.workbook.freeName(t.newSheetBase),
              ),
            ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < sheets.length; i++)
                  _tab(context, sheets[i], i, i == c.activeIndex),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, Sheet sheet, int index, bool active) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => c.activeIndex = index,
      onLongPress: widget.readOnly ? null : () => _sheetMenu(context, sheet),
      onSecondaryTap: widget.readOnly ? null : () => _sheetMenu(context, sheet),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.surface : null,
          border: Border(
            top: BorderSide(
              width: 2,
              color: active ? theme.colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              sheet.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (active && !widget.readOnly)
              InkWell(
                onTap: () => _sheetMenu(context, sheet),
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.arrow_drop_down, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sheetMenu(BuildContext context, Sheet sheet) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t.rename),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            if (c.workbook.sheets.length > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(t.delete),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'rename') {
      await _rename(context, sheet);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(sheet.name),
          content: Text(t.deleteSheetQuestion),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.delete),
            ),
          ],
        ),
      );
      if (ok == true) c.removeSheet(sheet);
    }
  }

  Future<void> _rename(BuildContext context, Sheet sheet) async {
    final text = TextEditingController(text: sheet.name);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void submit() {
            try {
              c.renameSheet(sheet, text.text);
              Navigator.of(ctx).pop();
            } on ArgumentError catch (e) {
              setLocal(() => error = '${e.message}');
            }
          }

          return AlertDialog(
            title: Text(t.rename),
            content: TextField(
              controller: text,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.sheetName,
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(t.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(t.ok)),
            ],
          );
        },
      ),
    );
    text.dispose();
  }
}
