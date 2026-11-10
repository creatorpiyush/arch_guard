import 'dart:collection';

import '../models/scan_result.dart';

/// One hop of an import path: a file-to-file edge, or the final hop into a
/// package.
class ImportStep {
  /// The file holding the directive.
  final String from;

  /// The file reached, or the directive's URI for a hop into a package.
  final String to;

  /// Directive kind: `import`, `export` or `part`.
  final String type;

  /// 1-based line of the directive in [from], if known.
  final int? line;

  /// The condition of a conditional import or export, if any.
  final String? condition;

  /// Creates a step.
  const ImportStep({
    required this.from,
    required this.to,
    required this.type,
    this.line,
    this.condition,
  });
}

/// Where [ImportPath.find] stops: some scanned files, or a package.
sealed class PathTarget {
  /// The target as shown to people: `lib/data/`, `package:flutter`.
  final String label;

  const PathTarget(this.label);
}

/// A target of one or more scanned files.
class FileTarget extends PathTarget {
  /// Project-relative paths of the target files.
  final Set<String> files;

  /// Creates a target of [files].
  const FileTarget(this.files, super.label);
}

/// A target package (`flutter`) or core library (`dart:io`).
class PackageTarget extends PathTarget {
  /// Package name as [PackageImport.package] holds it.
  final String package;

  /// Creates a target of [package].
  PackageTarget(this.package)
    : super(package.startsWith('dart:') ? package : 'package:$package');
}

/// Finds the shortest import path between files, folders and packages.
class ImportPath {
  /// The scanned files that the CLI argument [arg] names: an exact file, every
  /// file under a folder, or the one file whose path ends with `/<arg>`.
  /// Throws [ArgumentError] when nothing or more than one file matches.
  static Set<String> matchFiles(ScanResult result, String arg) {
    final (files, _) = _match(result, arg);
    if (files.isEmpty) {
      throw ArgumentError('no scanned file or folder matches "$arg".');
    }
    return files;
  }

  /// Resolves the `to` argument: `package:x` or `dart:x`, then a file or
  /// folder as for [matchFiles], then a bare package name (`flutter`).
  static PathTarget matchTarget(ScanResult result, String arg) {
    if (arg.startsWith('dart:')) return PackageTarget(arg);
    if (arg.startsWith('package:')) {
      final rest = arg.substring('package:'.length);
      final name = rest.split('/').first;
      // A scanned package's own files are files, not a package import.
      final lib =
          {for (final pkg in result.packages) pkg.name: pkg.libPath}[name] ??
          (name == result.packageName ? 'lib' : null);
      if (lib == null) return PackageTarget(name);
      final inner = rest.length > name.length
          ? rest.substring(name.length)
          : '';
      final (files, label) = _match(result, '$lib$inner');
      if (files.isEmpty) {
        throw ArgumentError('no scanned file or folder matches "$arg".');
      }
      return FileTarget(files, label);
    }
    final (files, label) = _match(result, arg);
    if (files.isNotEmpty) return FileTarget(files, label);
    if (result.packageImports.any((i) => i.package == arg)) {
      return PackageTarget(arg);
    }
    throw ArgumentError('no scanned file or folder matches "$arg".');
  }

  static (Set<String>, String) _match(ScanResult result, String arg) {
    var path = arg.replaceAll('\\', '/');
    if (path.startsWith('./')) path = path.substring(2);
    if (result.files.containsKey(path)) return ({path}, path);

    final dir = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final inDir = {
      for (final f in result.files.keys)
        if (f.startsWith('$dir/')) f,
    };
    if (inDir.isNotEmpty) return (inDir, '$dir/');

    final bySuffix = [
      for (final f in result.files.keys)
        if (f.endsWith('/$path')) f,
    ];
    if (bySuffix.length > 1) {
      final more = bySuffix.length > 5 ? ', ...' : '';
      throw ArgumentError(
        '"$arg" matches ${bySuffix.length} files: '
        '${bySuffix.take(5).join(', ')}$more',
      );
    }
    return (bySuffix.toSet(), bySuffix.firstOrNull ?? path);
  }

  /// The shortest path from any of [from] to [to], following every edge in
  /// [result]. Returns `[]` when a [from] file is itself a target, and
  /// `null` when no path exists.
  static List<ImportStep>? find({
    required ScanResult result,
    required Set<String> from,
    required PathTarget to,
  }) {
    final starts = from.toList()..sort();
    if (to is FileTarget && starts.any(to.files.contains)) return [];

    final out = <String, List<GraphEdge>>{};
    for (final edge in result.edges) {
      (out[edge.from] ??= []).add(edge);
    }
    final packageHops = <String, List<PackageImport>>{};
    if (to is PackageTarget) {
      for (final i in result.packageImports) {
        if (i.package == to.package) (packageHops[i.file] ??= []).add(i);
      }
    }

    final parent = <String, ImportStep>{};
    List<ImportStep> pathTo(String file, [ImportStep? last]) {
      final steps = [?last];
      for (var step = parent[file]; step != null; step = parent[step.from]) {
        steps.add(step);
      }
      return steps.reversed.toList();
    }

    final seen = {...starts};
    final queue = Queue.of(starts);
    while (queue.isNotEmpty) {
      final file = queue.removeFirst();
      final hop = packageHops[file]?.first;
      if (hop != null) {
        return pathTo(
          file,
          ImportStep(from: file, to: hop.uri, type: hop.type, line: hop.line),
        );
      }
      for (final edge in out[file] ?? const <GraphEdge>[]) {
        if (!seen.add(edge.to)) continue;
        parent[edge.to] = ImportStep(
          from: file,
          to: edge.to,
          type: edge.type,
          line: edge.line,
          condition: edge.condition,
        );
        if (to is FileTarget && to.files.contains(edge.to)) {
          return pathTo(edge.to);
        }
        queue.add(edge.to);
      }
    }
    return null;
  }
}
