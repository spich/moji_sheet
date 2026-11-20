/// A reference to cells on another sheet, found in a formula.
class SheetRef {
  const SheetRef(this.sheet, this.reference);

  /// Sheet name as written (without the surrounding quotes).
  final String sheet;

  /// Cell or range in A1 notation, without `$` markers (`A1`, `B2:C10`).
  final String reference;

  bool get isRange => reference.contains(':');
}

/// A formula in which every `Sheet!A1` reference has been replaced by a
/// placeholder name.
class RewrittenFormula {
  const RewrittenFormula(this.formula, this.refs);

  final String formula;

  /// Placeholder name → the reference it stands for.
  final Map<String, SheetRef> refs;
}

/// The formula engine parses `Sheet2!A1` but evaluates it as `A1` of the
/// sheet being calculated — the sheet name is dropped. Its AST is sealed, so
/// the reference cannot be given its own node either.
///
/// Instead the reference is replaced by a bare name before parsing
/// (`=Sheet2!A1+1` → `=mojisheetref_a+1`). The engine resolves bare names
/// through `EvaluationContext.getVariable`, where the workbook returns the
/// value from the right sheet.
class SheetRefRewriter {
  const SheetRefRewriter._();

  static const prefix = 'mojisheetref_';

  static final _ref = RegExp(
    r"(?:'((?:[^']|'')+)'|([A-Za-z_À-ɏ][A-Za-z0-9_.À-ɏ]*))"
    r'!(\$?[A-Za-z]{1,3}\$?\d+(?::\$?[A-Za-z]{1,3}\$?\d+)?)',
  );

  /// Whether [formula] may contain a sheet-qualified reference.
  static bool mayContain(String formula) => formula.contains('!');

  static RewrittenFormula rewrite(String formula) {
    if (!mayContain(formula)) return RewrittenFormula(formula, const {});
    final refs = <String, SheetRef>{};
    final out = StringBuffer();
    var i = 0;
    while (i < formula.length) {
      final ch = formula[i];
      // Text literals are copied untouched ("a ""quoted"" b").
      if (ch == '"') {
        final end = _endOfString(formula, i);
        out.write(formula.substring(i, end));
        i = end;
        continue;
      }
      final m = _ref.matchAsPrefix(formula, i);
      if (m != null && _startsToken(formula, i)) {
        final sheet = (m.group(1)?.replaceAll("''", "'")) ?? m.group(2)!;
        final name = '$prefix${_letters(refs.length)}';
        refs[name] = SheetRef(sheet, m.group(3)!.replaceAll(r'$', '').toUpperCase());
        out.write(name);
        i = m.end;
        continue;
      }
      out.write(ch);
      i++;
    }
    return RewrittenFormula(out.toString(), refs);
  }

  static int _endOfString(String s, int start) {
    var i = start + 1;
    while (i < s.length) {
      if (s[i] == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          i += 2;
          continue;
        }
        return i + 1;
      }
      i++;
    }
    return s.length;
  }

  /// A reference starts a token: it is not the tail of a longer identifier.
  static bool _startsToken(String s, int i) {
    if (i == 0) return true;
    final p = s.codeUnitAt(i - 1);
    final isWord = (p >= 0x30 && p <= 0x39) ||
        (p >= 0x41 && p <= 0x5A) ||
        (p >= 0x61 && p <= 0x7A) ||
        p == 0x5F ||
        p == 0x2E;
    return !isWord;
  }

  /// 0 → a, 25 → z, 26 → aa (the engine's names take letters only).
  static String _letters(int n) {
    final b = StringBuffer();
    var v = n;
    do {
      b.write(String.fromCharCode(0x61 + v % 26));
      v = v ~/ 26 - 1;
    } while (v >= 0);
    return b.toString().split('').reversed.join();
  }

  /// Quotes a sheet name for use in a formula when it needs quoting.
  static String quote(String sheet) {
    final plain = RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(sheet);
    return plain ? sheet : "'${sheet.replaceAll("'", "''")}'";
  }
}
