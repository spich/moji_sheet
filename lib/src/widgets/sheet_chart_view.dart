import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../model/sheet_chart.dart';
import '../model/workbook.dart';

/// Colours of chart series, in order.
const List<Color> sheetChartPalette = [
  Color(0xFF4472C4),
  Color(0xFFED7D31),
  Color(0xFF70AD47),
  Color(0xFFFFC000),
  Color(0xFF7030A0),
  Color(0xFF00B0F0),
  Color(0xFFC00000),
  Color(0xFF7F7F7F),
];

/// Draws a [SheetChart] from the current values of [sheet].
class SheetChartView extends StatelessWidget {
  const SheetChartView({
    super.key,
    required this.chart,
    required this.sheet,
    this.emptyText = 'No numbers in this range.',
  });

  final SheetChart chart;
  final Sheet sheet;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final data = chart.read(sheet);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chart.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              chart.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
          ),
        Expanded(
          child: data.isEmpty
              ? Center(
                  child: Text(emptyText, style: theme.textTheme.bodySmall),
                )
              : switch (chart.type) {
                  SheetChartType.bar => _bar(context, data),
                  SheetChartType.line => _line(context, data),
                  SheetChartType.pie => _pie(context, data),
                },
        ),
        if (!data.isEmpty && _showLegend(data))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: _legend(context, data),
            ),
          ),
      ],
    );
  }

  bool _showLegend(ChartData d) =>
      chart.type == SheetChartType.pie ||
      d.series.length > 1 ||
      d.series.any((s) => s.name.isNotEmpty);

  List<Widget> _legend(BuildContext context, ChartData d) {
    final names = chart.type == SheetChartType.pie
        ? d.labels
        : [for (final s in d.series) s.name];
    return [
      for (var i = 0; i < names.length; i++)
        if (names[i].isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                color: sheetChartPalette[i % sheetChartPalette.length],
              ),
              const SizedBox(width: 4),
              Text(names[i], style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
    ];
  }

  FlTitlesData _titles(BuildContext context, ChartData d) {
    final style = Theme.of(context).textTheme.bodySmall;
    // Show at most ~8 labels so they do not overlap.
    final step = (d.labels.length / 8).ceil().clamp(1, 1 << 20);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 46,
          // The axis ends would print on top of the nearest round value.
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(_short(v), style: style),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.round();
            if (i < 0 || i >= d.labels.length || i % step != 0 || v != i) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(
                d.labels[i],
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }

  String _short(double v) {
    final sep = sheet.workbook?.locale.decimalSeparator ?? '.';
    String dec(double x, int digits) =>
        x.toStringAsFixed(digits).replaceFirst('.', sep);
    final a = v.abs();
    if (a >= 1e9) return '${dec(v / 1e9, 1)}G';
    if (a >= 1e6) return '${dec(v / 1e6, 1)}M';
    if (a >= 1e4) return '${dec(v / 1e3, 0)}k';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return dec(v, a < 10 ? 2 : 1);
  }

  Widget _bar(BuildContext context, ChartData d) => BarChart(
        BarChartData(
          titlesData: _titles(context, d),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(drawVerticalLine: false),
          barGroups: [
            for (var i = 0; i < d.labels.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  for (var s = 0; s < d.series.length; s++)
                    BarChartRodData(
                      toY: d.series[s].values[i] ?? 0,
                      color: sheetChartPalette[s % sheetChartPalette.length],
                      width: d.series.length > 3 ? 5 : 10,
                      borderRadius: BorderRadius.zero,
                    ),
                ],
              ),
          ],
        ),
      );

  Widget _line(BuildContext context, ChartData d) => LineChart(
        LineChartData(
          // Room at both ends, so the first and last label are not cut off.
          minX: -0.4,
          maxX: d.labels.length - 1 + 0.4,
          titlesData: _titles(context, d),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(drawVerticalLine: false),
          lineBarsData: [
            for (var s = 0; s < d.series.length; s++)
              LineChartBarData(
                color: sheetChartPalette[s % sheetChartPalette.length],
                barWidth: 2,
                dotData: FlDotData(show: d.labels.length <= 24),
                spots: [
                  for (var i = 0; i < d.labels.length; i++)
                    // A cell without a number breaks the line instead of
                    // being drawn as zero.
                    d.series[s].values[i] == null
                        ? FlSpot.nullSpot
                        : FlSpot(i.toDouble(), d.series[s].values[i]!),
                ],
              ),
          ],
        ),
      );

  Widget _pie(BuildContext context, ChartData d) {
    final values = d.series.first.values;
    final total = values.fold<double>(0, (a, v) => a + ((v ?? 0) > 0 ? v! : 0));
    return PieChart(
      PieChartData(
        sectionsSpace: 1,
        centerSpaceRadius: 0,
        sections: [
          for (var i = 0; i < values.length; i++)
            // A pie has no meaning for zero or negative parts.
            if ((values[i] ?? 0) > 0)
              PieChartSectionData(
                value: values[i]!,
                color: sheetChartPalette[i % sheetChartPalette.length],
                radius: 70,
                title: total == 0
                    ? ''
                    : '${(values[i]! / total * 100).toStringAsFixed(0)}%',
                titleStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
        ],
      ),
    );
  }
}
