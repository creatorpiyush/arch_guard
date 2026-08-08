import 'package:path/path.dart' as p;

/// Directive extracted from a file (import or export).
class ExtractedDirective {
  final String uri;
  final String type; // 'import' or 'export'

  const ExtractedDirective(this.uri, {this.type = 'import'});
}

/// Fast regex-based parser for Dart `import` and `export` directives.
class ImportReader {
  // Matches every quoted URI on an import/export directive line.
  static final RegExp _directiveLineRegex = RegExp(
    r'^\s*(import|export)\s+.*?;',
    multiLine: true,
  );

  static final RegExp _quotedUriRegex = RegExp(r'''['"]([^'"]+)['"]''');

  /// Reads [content] and returns all raw import/export URIs.
  static List<ExtractedDirective> extractDirectives(String content) {
    final results = <ExtractedDirective>[];

    // Remove block comments /* ... */
    final noBlockComments = content.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

    // Pre-pass: sanitize lines and join multi-line import/export statements
    final lines = noBlockComments.split('\n');
    final processedBuffer = StringBuffer();

    bool inDirective = false;

    for (var line in lines) {
      // Strip single line comments `// ...` unless inside strings
      final commentIdx = line.indexOf('//');
      var sanitized = commentIdx != -1 ? line.substring(0, commentIdx) : line;

      final trimmed = sanitized.trim();
      if (trimmed.isEmpty) continue;

      final isDirectiveStart = RegExp(
        r'^(import|export)(\s+|$)',
      ).hasMatch(trimmed);

      if (isDirectiveStart || inDirective) {
        processedBuffer.write(' ');
        processedBuffer.write(trimmed);
        if (trimmed.endsWith(';')) {
          inDirective = false;
          processedBuffer.writeln();
        } else {
          inDirective = true;
        }
      }
    }

    final sanitizedContent = processedBuffer.toString();

    for (final match in _directiveLineRegex.allMatches(sanitizedContent)) {
      final directiveLine = match.group(0)!;
      final directiveType = directiveLine.trimLeft().startsWith('export')
          ? 'export'
          : 'import';

      for (final uriMatch in _quotedUriRegex.allMatches(directiveLine)) {
        results.add(
          ExtractedDirective(uriMatch.group(1)!, type: directiveType),
        );
      }
    }

    return results;
  }

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
