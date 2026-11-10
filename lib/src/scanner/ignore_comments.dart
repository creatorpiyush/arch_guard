/// The `// ignore: arch_guard_lint/<code>` and
/// `// ignore_for_file: arch_guard_lint/<code>` comments of one file, read the
/// way the analyzer reads them, so the CLI silences what the IDE silences.
class IgnoreComments {
  /// Code that silences a layer rule violation.
  static const layerViolation = 'layer_violation';

  /// Code that silences a forbidden package import.
  static const forbiddenPackage = 'forbidden_package';

  /// Code that leaves an import out of cycle detection.
  static const circularDependency = 'circular_dependency';

  static const _prefix = 'arch_guard_lint/';
  static final _pattern = RegExp(r'^//\s*ignore(_for_file)?\s*:\s*(.+)$');

  /// Codes from `ignore_for_file` comments, which apply to every line.
  final Set<String> forFile;

  final Map<int, Set<String>> _byLine;

  IgnoreComments._(this.forFile, this._byLine);

  /// Codes (without the `arch_guard_lint/` prefix) that apply to the 1-based
  /// [line]: [forFile] plus any `ignore` comment for that line.
  Set<String> codesAt(int? line) => {...forFile, ...?_byLine[line]};

  /// Reads the ignore comments in [content]. Text inside string literals and
  /// block comments is skipped. A comment alone on its line applies to the
  /// next line; a comment after code applies to its own line.
  // ponytail: no string-interpolation nesting, so `'${'//'}'` can confuse it;
  // reuse the analyzer's scanner if that ever matters.
  static IgnoreComments parse(String content) {
    final forFile = <String>{};
    final byLine = <int, Set<String>>{};
    final n = content.length;
    var line = 1;
    var codeOnLine = false;
    var i = 0;

    while (i < n) {
      final c = content[i];
      if (c == '\n') {
        line++;
        codeOnLine = false;
        i++;
      } else if (c == ' ' || c == '\t' || c == '\r') {
        i++;
      } else if (content.startsWith('//', i)) {
        var end = content.indexOf('\n', i);
        if (end == -1) end = n;
        final match = _pattern.firstMatch(
          content.substring(i, end).trimRight(),
        );
        if (match != null) {
          final codes = [
            for (final raw in match.group(2)!.split(','))
              if (raw.trim().startsWith(_prefix))
                raw.trim().substring(_prefix.length),
          ];
          if (match.group(1) != null) {
            forFile.addAll(codes);
          } else {
            byLine
                .putIfAbsent(codeOnLine ? line : line + 1, () => {})
                .addAll(codes);
          }
        }
        i = end;
      } else if (content.startsWith('/*', i)) {
        var depth = 0;
        while (i < n) {
          if (content.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (content.startsWith('*/', i)) {
            i += 2;
            if (--depth == 0) break;
          } else {
            if (content[i] == '\n') line++;
            i++;
          }
        }
      } else if (c == '"' || c == "'") {
        final raw = i > 0 && (content[i - 1] == 'r' || content[i - 1] == 'R');
        final delimiter = content.startsWith(c * 3, i) ? c * 3 : c;
        i += delimiter.length;
        while (i < n && !content.startsWith(delimiter, i)) {
          if (!raw && content[i] == '\\') i++;
          if (i < n && content[i] == '\n') line++;
          i++;
        }
        i += delimiter.length;
        codeOnLine = true;
      } else {
        codeOnLine = true;
        i++;
      }
    }
    return IgnoreComments._(forFile, byLine);
  }
}
