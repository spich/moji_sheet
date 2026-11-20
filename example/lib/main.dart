import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moji_sheet/moji_sheet.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'moji_sheet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.orange),
        home: const ExamplePage(),
      );
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  late final MojiSheetController controller;

  @override
  void initState() {
    super.initState();
    controller = MojiSheetController(workbook: _demo());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// A Croatian-locale workbook: a price list, and a second sheet that sums it.
  static Workbook _demo() {
    final wb = Workbook(
      locale: SheetLocale.hr,
      sheets: [Sheet(name: 'Promet'), Sheet(name: 'Sažetak')],
    );
    final s = wb.sheets[0];
    const rows = [
      ['Mjesec', 'Usluge', 'Proizvodi'],
      ['Siječanj', '1.250,00', '430,50'],
      ['Veljača', '1.410,00', '512,00'],
      ['Ožujak', '1.980,50', '389,90'],
      ['Travanj', '2.150,00', '610,00'],
    ];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        s.setInput(r, c, rows[r][c]);
      }
    }
    s.setInput(5, 0, 'Ukupno');
    s.setInput(5, 1, '=SUM(B2:B5)');
    s.setInput(5, 2, '=SUM(C2:C5)');
    s.data.batchUpdateRaw((b) {
      for (var c = 0; c < 3; c++) {
        b.setStyle(
          CellCoordinate(0, c),
          const CellStyle(backgroundColor: Color(0xFFFFE0B2)),
        );
        b.setStyle(
          CellCoordinate(5, c),
          const CellStyle(backgroundColor: Color(0xFFDCEDC8)),
        );
      }
    });
    s.columnWidths[0] = 110;
    s.charts.add(
      SheetChart(
        type: SheetChartType.bar,
        range: const CellRange(0, 0, 4, 2),
        title: 'Promet po mjesecima',
      ),
    );

    final z = wb.sheets[1];
    z.setInput(0, 0, 'Ukupan promet');
    z.setInput(0, 1, '=Promet!B6+Promet!C6');
    z.setInput(1, 0, 'Prosjek usluga');
    z.setInput(1, 1, '=AVERAGE(Promet!B2:B5)');
    z.setInput(2, 0, 'Najbolji mjesec');
    z.setInput(2, 1, '=MAX(Promet!B2:B5)');
    z.setInput(3, 0, 'Udio proizvoda');
    z.setInput(3, 1, '=Promet!C6/B1');
    z.data.setFormat(const CellCoordinate(3, 1), CellFormat.percentageDecimal);
    z.columnWidths[0] = 150;
    return wb;
  }

  /// The example has no file picker: CSV comes from, and goes to, the
  /// clipboard. An app would use its own picker and storage here.
  Future<({String text, String? name})?> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      _say('The clipboard holds no text.');
      return null;
    }
    return (text: text, name: 'Uvoz');
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('moji_sheet'),
        toolbarHeight: 44,
        actions: [
          IconButton(
            tooltip: 'Save to JSON and load back',
            icon: const Icon(Icons.sync),
            onPressed: () {
              final json = controller.toJson();
              controller.loadJson(json);
              _say('Saved and reloaded ${json.length} characters of JSON.');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: MojiSheetView(
          controller: controller,
          strings: MojiSheetStrings.hr,
          onImportCsv: _importFromClipboard,
          onExportCsv: (csv, name) async {
            await Clipboard.setData(ClipboardData(text: csv));
            _say('CSV of "$name" copied to the clipboard.');
          },
        ),
      ),
    );
  }
}
