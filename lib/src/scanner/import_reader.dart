import 'package:path/path.dart' as p;

/// Directive extracted from a file (import, export or part).
class ExtractedDirective {
  /// The URI inside the directive's quotes.
  final String uri;

  /// Directive kind: `import`, `export` or `part`.
  final String type;

  /// 1-based line of the directive keyword, if known.
  final int? line;

  /// Creates a directive for [uri].
  const ExtractedDirective(this.uri, {this.type = 'import', this.line});
}

/// Lightweight Dart directive parser for `import`, `export` and `part` URIs.
///
/// Rather than building an AST, it walks the directive section at the top of
/// a file token by token, skipping comments and annotations, and stops at the
/// first declaration (Dart forbids directives after declarations). String
/// literals are read properly, so `//` or `/*` inside a URI, and code inside
/// later multi-line strings, never confuse it.
class ImportReader {
  /// Reads [content] and returns all raw import/export/part URIs.
  ///
  /// Conditional imports yield every candidate URI. `part of` and `library`
  /// directives yield nothing.
  static List<ExtractedDirective> extractDirectives(String content) =>
      _DirectiveScanner(content).scan();

  /// Resolves a raw [uri] to a package/repository-relative path.
  ///
  /// [workspacePackages] maps workspace package name -> relative lib directory path
  /// (e.g. `{'content_stream': 'packages/content_stream/lib'}`).
  static String? resolveUri({
    required String uri,
    required String packageName,
    required String importingFileRelativePath,
    Map<String, String>? workspacePackages,
  }) {
    if (uri.startsWith('dart:')) {
      return null;
    }

    if (uri.startsWith('package:')) {
      final selfPrefix = 'package:$packageName/';
      if (uri.startsWith(selfPrefix)) {
        final rest = uri.substring(selfPrefix.length);
        final baseLib =
            (workspacePackages != null &&
                workspacePackages.containsKey(packageName))
            ? workspacePackages[packageName]!
            : 'lib';
        return p.normalize(p.join(baseLib, rest)).replaceAll('\\', '/');
      }

      // Check workspace packages
      if (workspacePackages != null && workspacePackages.isNotEmpty) {
        final match = RegExp(r'^package:([^/]+)/(.*)$').firstMatch(uri);
        if (match != null) {
          final targetPkgName = match.group(1)!;
          final restPath = match.group(2)!;
          if (workspacePackages.containsKey(targetPkgName)) {
            final targetLibDir = workspacePackages[targetPkgName]!;
            return p
                .normalize(p.join(targetLibDir, restPath))
                .replaceAll('\\', '/');
          }
        }
      }

      // External package dependency
      return null;
    }

    // Relative import
    final importingDir = p.dirname(importingFileRelativePath);
    final resolved = p
        .normalize(p.join(importingDir, uri))
        .replaceAll('\\', '/');
    return resolved;
  }
}

class _DirectiveScanner {
  final String src;
  int pos = 0;

  _DirectiveScanner(this.src);

  static const _quote1 = 0x27; // '
  static const _quote2 = 0x22; // "

  bool get _atEnd => pos >= src.length;

  // Incremental offset -> line conversion; directives are read in order.
  int _lineOffset = 0;
  int _line = 1;

  /// Returns the 1-based line containing [offset] (must not decrease).
  int _lineAt(int offset) {
    for (; _lineOffset < offset && _lineOffset < src.length; _lineOffset++) {
      if (src.codeUnitAt(_lineOffset) == 0x0A) _line++;
    }
    return _line;
  }

  int _char([int offset = 0]) =>
      pos + offset < src.length ? src.codeUnitAt(pos + offset) : -1;

  List<ExtractedDirective> scan() {
    final results = <ExtractedDirective>[];

    if (src.startsWith('\uFEFF')) pos = 1;
    if (src.startsWith('#!', pos)) _skipToLineEnd();

    while (true) {
      _skipTrivia();
      if (_atEnd) break;

      if (src[pos] == '@') {
        _skipAnnotation();
        continue;
      }

      final keyword = _peekIdentifier();
      final line = _lineAt(pos);
      switch (keyword) {
        case 'import' || 'export':
          pos += keyword.length;
          final (:uris, firstWord: _) = _readStatement();
          results.addAll(
            uris.map((u) => ExtractedDirective(u, type: keyword, line: line)),
          );
        case 'part':
          pos += keyword.length;
          final (:uris, :firstWord) = _readStatement();
          if (firstWord != 'of') {
            results.addAll(
              uris.map((u) => ExtractedDirective(u, type: 'part', line: line)),
            );
          }
        case 'library':
          pos += keyword.length;
          _readStatement();
        default:
          // First declaration: no further directives are legal.
          return results;
      }
    }

    return results;
  }

  /// Consumes a directive up to and including `;`. Returns the string literals
  /// found outside parentheses (so `if (dart.library.io == 'true')` conditions
  /// are skipped) and the first identifier token, if the statement starts with one.
  ({List<String> uris, String? firstWord}) _readStatement() {
    final uris = <String>[];
    String? firstWord;
    var sawToken = false;
    var depth = 0;

    while (true) {
      _skipTrivia();
      if (_atEnd) break;
      final c = src[pos];

      if (c == ';') {
        pos++;
        break;
      }

      final literal = _tryReadString();
      if (literal != null) {
        if (depth == 0) uris.add(literal);
        sawToken = true;
        continue;
      }

      final word = _peekIdentifier();
      if (word.isNotEmpty) {
        if (!sawToken) firstWord = word;
        pos += word.length;
      } else {
        if (c == '(') depth++;
        if (c == ')' && depth > 0) depth--;
        pos++;
      }
      sawToken = true;
    }

    return (uris: uris, firstWord: firstWord);
  }

  /// Skips `@name`, `@prefix.name` or `@name(...)` metadata.
  void _skipAnnotation() {
    pos++; // '@'
    while (true) {
      _skipTrivia();
      final word = _peekIdentifier();
      if (word.isEmpty) break;
      pos += word.length;
      _skipTrivia();
      if (src.startsWith('.', pos)) {
        pos++;
        continue;
      }
      break;
    }
    _skipTrivia();
    if (src.startsWith('(', pos)) {
      var depth = 0;
      while (!_atEnd) {
        _skipTrivia();
        if (_atEnd) break;
        if (_tryReadString() != null) continue;
        final c = src[pos++];
        if (c == '(') depth++;
        if (c == ')' && --depth == 0) break;
      }
    }
  }

  /// Reads a (possibly raw or triple-quoted) string literal at [pos] and
  /// returns its contents, or returns `null` without moving if none starts here.
  String? _tryReadString() {
    var start = pos;
    var raw = false;
    if ((_char() == 0x72 || _char() == 0x52) && // r or R
        (_char(1) == _quote1 || _char(1) == _quote2)) {
      raw = true;
      start++;
    }
    final q = start < src.length ? src.codeUnitAt(start) : -1;
    if (q != _quote1 && q != _quote2) return null;

    final quote = String.fromCharCode(q);
    final delimiter = src.startsWith(quote * 3, start) ? quote * 3 : quote;
    pos = start + delimiter.length;
    final contentStart = pos;

    while (!_atEnd) {
      if (!raw && src[pos] == '\\') {
        pos += 2;
        continue;
      }
      if (src.startsWith(delimiter, pos)) {
        final value = src.substring(contentStart, pos);
        pos += delimiter.length;
        return value;
      }
      pos++;
    }
    return src.substring(contentStart);
  }

  /// Skips whitespace, `//` line comments and (nestable) `/* */` block comments.
  void _skipTrivia() {
    while (!_atEnd) {
      final c = _char();
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        pos++;
      } else if (src.startsWith('//', pos)) {
        _skipToLineEnd();
      } else if (src.startsWith('/*', pos)) {
        var depth = 0;
        while (!_atEnd) {
          if (src.startsWith('/*', pos)) {
            depth++;
            pos += 2;
          } else if (src.startsWith('*/', pos)) {
            pos += 2;
            if (--depth == 0) break;
          } else {
            pos++;
          }
        }
      } else {
        break;
      }
    }
  }

  void _skipToLineEnd() {
    final newline = src.indexOf('\n', pos);
    pos = newline == -1 ? src.length : newline + 1;
  }

  /// Returns the identifier starting at [pos] (without consuming it), or ''.
  String _peekIdentifier() {
    var end = pos;
    while (end < src.length && _isIdentifierChar(src.codeUnitAt(end))) {
      end++;
    }
    if (end == pos || _isDigit(src.codeUnitAt(pos))) return '';
    return src.substring(pos, end);
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isIdentifierChar(int c) =>
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x41 && c <= 0x5A) || // A-Z
      _isDigit(c) ||
      c == 0x5F || // _
      c == 0x24; // $
}
