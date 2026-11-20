import 'package:worksheet/worksheet.dart'
    show CellFormat, CellFormatResult, CellFormatType, CellValue, FormatLocale;

/// Result of recognising a number typed or imported as text.
class ParsedNumber {
  const ParsedNumber(this.value, [this.format]);

  /// The numeric value (a percentage is stored as a fraction: `12,5 %` → 0.125).
  final double value;

  /// Display format implied by the input (percentage, currency), if any.
  final CellFormat? format;
}

/// Regional conventions of a workbook: how numbers and dates are typed and
/// shown, and which delimiter CSV files use.
///
/// The underlying grid understands grouped numbers in its own locales, but
/// not plain decimal commas (`1234,5`), percentages with a space (`12,5 %`)
/// or a trailing currency symbol (`1.234,50 €`). [parseNumber] covers those.
class SheetLocale {
  const SheetLocale({
    required this.code,
    required this.format,
    required this.csvDelimiter,
    this.dateFormat = 'dd.mm.yyyy',
  });

  /// Language tag, e.g. `hr`, `en-US`.
  final String code;

  /// Separators, month names and day order used by the grid.
  final FormatLocale format;

  /// Field delimiter spreadsheets in this region write to CSV.
  final String csvDelimiter;

  /// Format code applied to dates that carry no format of their own.
  final String dateFormat;

  /// [format] as the grid must receive it to paint in this locale.
  ///
  /// The grid formats cells without passing a locale, so a plain format would
  /// always be drawn with English separators and month names.
  CellFormat forDisplay(CellFormat format) =>
      format is LocalizedCellFormat ? format : LocalizedCellFormat(format, this.format);

  String get decimalSeparator => format.decimalSeparator;
  String get thousandsSeparator => format.thousandsSeparator;

  static const _hrMonths = [
    'siječanj', 'veljača', 'ožujak', 'travanj', 'svibanj', 'lipanj',
    'srpanj', 'kolovoz', 'rujan', 'listopad', 'studeni', 'prosinac',
  ];
  static const _hrMonthsAbbr = [
    'sij', 'velj', 'ožu', 'tra', 'svi', 'lip',
    'srp', 'kol', 'ruj', 'lis', 'stu', 'pro',
  ];
  static const _hrDays = [
    'ponedjeljak', 'utorak', 'srijeda', 'četvrtak', 'petak', 'subota',
    'nedjelja',
  ];
  static const _hrDaysAbbr = ['pon', 'uto', 'sri', 'čet', 'pet', 'sub', 'ned'];

  /// Croatian: `1.234,50`, `20.11.2026.`, semicolon-separated CSV.
  static const hr = SheetLocale(
    code: 'hr',
    format: FormatLocale(
      monthNames: _hrMonths,
      monthAbbr: _hrMonthsAbbr,
      dayNames: _hrDays,
      dayAbbr: _hrDaysAbbr,
      decimalSeparator: ',',
      thousandsSeparator: '.',
      currencySymbol: '€',
      dayFirst: true,
    ),
    csvDelimiter: ';',
    dateFormat: 'd.m.yyyy.',
  );

  /// German: `1.234,50`, `20.11.2026`, semicolon-separated CSV.
  static const de = SheetLocale(
    code: 'de',
    format: FormatLocale.deDe,
    csvDelimiter: ';',
  );

  /// US English: `1,234.50`, `11/20/2026`, comma-separated CSV.
  static const enUs = SheetLocale(
    code: 'en-US',
    format: FormatLocale.enUs,
    csvDelimiter: ',',
    dateFormat: 'm/d/yyyy',
  );

  /// British English: `1,234.50`, `20/11/2026`, comma-separated CSV.
  static const enGb = SheetLocale(
    code: 'en-GB',
    format: FormatLocale.enGb,
    csvDelimiter: ',',
    dateFormat: 'dd/mm/yyyy',
  );

  /// French: `1 234,50`, `20/11/2026`, semicolon-separated CSV.
  static const fr = SheetLocale(
    code: 'fr',
    format: FormatLocale.frFr,
    csvDelimiter: ';',
    dateFormat: 'dd/mm/yyyy',
  );

  static const List<SheetLocale> values = [hr, de, enUs, enGb, fr];

  /// The locale for a language tag (`hr`, `hr-HR`, `en_US`); [enUs] when the
  /// language is not known.
  static SheetLocale forCode(String? tag) {
    final t = (tag ?? '').replaceAll('_', '-').toLowerCase();
    for (final l in values) {
      if (l.code.toLowerCase() == t) return l;
    }
    final lang = t.split('-').first;
    return switch (lang) {
      'hr' || 'bs' || 'sr' || 'sl' => hr,
      'de' => de,
      'fr' => fr,
      'en' => t.endsWith('gb') ? enGb : enUs,
      _ => enUs,
    };
  }

  static const _currencySymbols = ['€', r'$', '£', 'kn', 'EUR', 'USD', 'GBP'];

  /// Recognises a number written in this locale, or returns `null`.
  ///
  /// Accepts an optional sign, thousands separators, a decimal part, a
  /// percent sign and a leading or trailing currency symbol. Text that only
  /// looks numeric in another locale (`1,234.50` under [hr]) is rejected, so
  /// that it is not silently read as a different value.
  ParsedNumber? parseNumber(String input) {
    var s = input.trim().replaceAll(' ', ' ').replaceAll(' ', ' ');
    if (s.isEmpty) return null;

    var percent = false;
    if (s.endsWith('%')) {
      percent = true;
      s = s.substring(0, s.length - 1).trimRight();
    }

    String? currency;
    for (final c in _currencySymbols) {
      if (s.endsWith(c)) {
        currency = c;
        s = s.substring(0, s.length - c.length).trimRight();
        break;
      }
      if (s.startsWith(c)) {
        currency = c;
        s = s.substring(c.length).trimLeft();
        break;
      }
    }
    if (percent && currency != null) return null;

    var negative = false;
    if (s.startsWith('-') || s.startsWith('+') || s.startsWith('−')) {
      negative = !s.startsWith('+');
      s = s.substring(1).trimLeft();
    }
    if (s.isEmpty) return null;

    final dec = RegExp.escape(decimalSeparator);
    // A narrow or regular space is accepted wherever the locale groups by
    // space; other locales group only by their own separator.
    final grp = thousandsSeparator.trim().isEmpty
        ? r'[ ]'
        : RegExp.escape(thousandsSeparator);
    final re = RegExp('^(?:(\\d{1,3}(?:$grp\\d{3})+)|(\\d+))(?:$dec(\\d+))?\$');
    final m = re.firstMatch(s);
    if (m == null) return null;

    final whole = (m.group(1) ?? m.group(2)!).replaceAll(RegExp(r'\D'), '');
    final frac = m.group(3) ?? '';
    final parsed = double.tryParse(frac.isEmpty ? whole : '$whole.$frac');
    if (parsed == null) return null;
    var value = negative ? -parsed : parsed;

    if (percent) {
      value = value / 100;
      return ParsedNumber(
        value,
        CellFormat(
          type: CellFormatType.percentage,
          formatCode: frac.isEmpty ? '0%' : '0.${'0' * frac.length}%',
        ),
      );
    }
    if (currency != null) {
      return ParsedNumber(
        value,
        CellFormat(
          type: CellFormatType.currency,
          formatCode: '#,##0.00 "$currency"',
        ),
      );
    }
    if (m.group(1) != null) {
      // Typed with thousands separators: keep them on display.
      return ParsedNumber(
        value,
        CellFormat(
          type: CellFormatType.number,
          formatCode: frac.isEmpty ? '#,##0' : '#,##0.${'0' * frac.length}',
        ),
      );
    }
    return ParsedNumber(value);
  }

  /// Format for a number that carries none, so that it is displayed with this
  /// locale's decimal separator and exactly the decimals it has (at most
  /// [maxDecimals]). Whole numbers need no format and yield `null`.
  CellFormat? defaultNumberFormat(double value, {int maxDecimals = 6}) {
    if (value.isNaN || value.isInfinite) return null;
    if (value == value.truncateToDouble()) return null;
    var text = value.abs().toStringAsFixed(maxDecimals);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    final decimals = text.length - text.indexOf('.') - 1;
    if (decimals <= 0) return null;
    return CellFormat(
      type: CellFormatType.number,
      formatCode: '0.${'0' * decimals}',
    );
  }

  /// A number as this locale writes it, without grouping (`1234,5`).
  String formatNumber(double value, {int maxDecimals = 6}) {
    if (value == value.truncateToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    var text = value.toStringAsFixed(maxDecimals);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text.replaceFirst('.', decimalSeparator);
  }
}

/// A [CellFormat] that always formats in one locale, whatever the caller
/// passes. Equal to the plain format with the same type and code.
class LocalizedCellFormat extends CellFormat {
  LocalizedCellFormat(CellFormat format, this.locale)
      : super(type: format.type, formatCode: format.formatCode);

  final FormatLocale locale;

  @override
  CellFormatResult formatRich(
    CellValue value, {
    double? availableWidth,
    FormatLocale? locale,
  }) =>
      super.formatRich(
        value,
        availableWidth: availableWidth,
        locale: this.locale,
      );
}
