import 'file_node.dart';
import 'workspace_package.dart';

/// Represents a directed edge from [from] to [to] in the dependency graph.
class GraphEdge {
  /// Relative path of the importing/exporting file.
  final String from;

  /// Relative path of the imported/exported file.
  final String to;

  /// The original directive type ('import', 'export' or 'part').
  final String type;

  /// 1-based line of the directive in [from], if known. Not part of equality.
  final int? line;

  /// For a conditional import or export, the condition that selects this
  /// URI (`dart.library.io`), or `default` for the fallback URI. `null` for
  /// a plain directive, which every platform compiles.
  final String? condition;

  /// Creates an edge from [from] to [to].
  const GraphEdge({
    required this.from,
    required this.to,
    this.type = 'import',
    this.line,
    this.condition,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphEdge &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to &&
          type == other.type &&
          condition == other.condition;

  @override
  int get hashCode => Object.hash(from, to, type, condition);

  @override
  String toString() =>
      '$from --($type${condition == null ? '' : ' if $condition'})--> $to';
}

/// A directive that points outside the scanned files: another package
/// (`package:dio/dio.dart`) or a core library (`dart:io`).
class PackageImport {
  /// Relative path of the importing/exporting file.
  final String file;

  /// The URI as written in the directive.
  final String uri;

  /// Package name (`dio`) or core library (`dart:io`) that [uri] points into.
  final String package;

  /// Directive kind: `import` or `export`.
  final String type;

  /// 1-based line of the directive in [file], if known.
  final int? line;

  /// Creates a record of [file] importing [uri].
  const PackageImport({
    required this.file,
    required this.uri,
    required this.package,
    this.type = 'import',
    this.line,
  });

  /// Returns `dio` for `package:dio/...`, `dart:io` for `dart:io`, or `null`
  /// for relative and malformed URIs.
  static String? packageOf(String uri) {
    if (uri.startsWith('dart:')) return uri;
    if (!uri.startsWith('package:')) return null;
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    return slash <= 0 ? null : rest.substring(0, slash);
  }

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'file': file,
    'uri': uri,
    'package': package,
    'type': type,
    'line': ?line,
  };
}

/// Holds the output of scanning a project repository.
class ScanResult {
  /// Name of the scanned package (from `pubspec.yaml`).
  final String packageName;

  /// Map of scanned files by relative path (e.g., `lib/auth.dart` or `packages/auth/lib/auth.dart`).
  final Map<String, FileNode> files;

  /// Directed edges between files in the project.
  final List<GraphEdge> edges;

  /// Number of member packages discovered if scanning in workspace/monorepo mode.
  final int workspacePackageCount;

  /// Files that matched the scan but could not be read, with the reason.
  final Map<String, String> skippedFiles;

  /// `package:` and `dart:` directives that point outside the importing
  /// file's own package, sorted by file and line.
  final List<PackageImport> packageImports;

  /// Workspace member packages (empty for a single package), sorted by path.
  final List<WorkspacePackage> packages;

  /// Creates a scan result.
  const ScanResult({
    required this.packageName,
    required this.files,
    required this.edges,
    this.workspacePackageCount = 1,
    this.skippedFiles = const {},
    this.packageImports = const [],
    this.packages = const [],
  });

  /// Whether this scan result represents a workspace/monorepo scan.
  bool get isWorkspace => workspacePackageCount > 1;

  /// Returns unique relative paths of all scanned files.
  List<String> get nodePaths => files.keys.toList();
}
