import 'file_node.dart';

/// Represents a directed edge from [from] to [to] in the dependency graph.
class GraphEdge {
  /// Relative path of the importing/exporting file.
  final String from;

  /// Relative path of the imported/exported file.
  final String to;

  /// The original directive type ('import' or 'export').
  final String type;

  const GraphEdge({required this.from, required this.to, this.type = 'import'});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphEdge &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to &&
          type == other.type;

  @override
  int get hashCode => Object.hash(from, to, type);

  @override
  String toString() => '$from --($type)--> $to';
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

  const ScanResult({
    required this.packageName,
    required this.files,
    required this.edges,
    this.workspacePackageCount = 1,
  });

  /// Whether this scan result represents a workspace/monorepo scan.
  bool get isWorkspace => workspacePackageCount > 1;

  /// Returns unique relative paths of all scanned files.
  List<String> get nodePaths => files.keys.toList();
}
