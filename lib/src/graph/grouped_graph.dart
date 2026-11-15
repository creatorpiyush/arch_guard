import '../analysis/arch_analysis.dart';
import '../checker/layer_validator.dart';
import '../checker/module_validator.dart';
import '../checker/workspace_validator.dart';

/// How [GroupedGraph] groups files.
const groupByValues = ['layer', 'module', 'package', 'folder'];

/// An edge between two groups of a [GroupedGraph].
class GroupEdge {
  /// The importing group.
  final String from;

  /// The imported group.
  final String to;

  /// File-to-file imports, exports and parts from [from] into [to].
  final int count;

  /// Layer, module and workspace rule violations from [from] into [to].
  final int violations;

  /// Creates an edge.
  const GroupEdge(this.from, this.to, this.count, this.violations);
}

/// The dependency graph with one node per layer, module, workspace package
/// or folder instead of one per file.
class GroupedGraph {
  /// The group of files that belong to no layer, module or package.
  static const none = '(none)';

  /// One of [groupByValues].
  final String groupBy;

  /// Group name to its files, both sorted.
  final Map<String, List<String>> groups;

  /// Edges between different groups, sorted by [GroupEdge.from] then
  /// [GroupEdge.to]. Imports inside a group are not edges.
  final List<GroupEdge> edges;

  /// Creates a grouped graph.
  const GroupedGraph(this.groupBy, this.groups, this.edges);

  /// Groups the files of [analysis] by [groupBy] (one of [groupByValues]).
  /// With [files], only those files and the edges between them are kept.
  static GroupedGraph build(
    ArchAnalysis analysis, {
    required String groupBy,
    Set<String>? files,
  }) {
    final config = analysis.config;
    final scan = analysis.scan;
    final String? Function(String) groupOf;
    switch (groupBy) {
      case 'layer':
        groupOf = LayerValidator.layerResolver(config);
      case 'module':
        final moduleOf = ModuleValidator.moduleResolver(config);
        groupOf = (f) => moduleOf(f)?.name;
      case 'package':
        final memberOf = WorkspaceValidator.memberResolver(scan.packages);
        groupOf = scan.packages.isEmpty
            ? (_) => scan.packageName
            : (f) => memberOf(f)?.name;
      case 'folder':
        groupOf = folderOf;
      default:
        throw ArgumentError.value(groupBy, 'groupBy');
    }
    final kept = files ?? scan.files.keys.toSet();
    final cache = <String, String>{};
    String group(String file) =>
        cache.putIfAbsent(file, () => groupOf(file) ?? none);

    final groups = <String, List<String>>{};
    for (final file in kept) {
      (groups[group(file)] ??= []).add(file);
    }

    final counts = <(String, String), int>{};
    for (final e in scan.edges) {
      if (!kept.contains(e.from) || !kept.contains(e.to)) continue;
      final pair = (group(e.from), group(e.to));
      if (pair.$1 != pair.$2) counts[pair] = (counts[pair] ?? 0) + 1;
    }
    final violations = <(String, String), int>{};
    for (final (from, to) in [
      for (final v in analysis.layerViolations) (v.sourceFile, v.targetFile),
      for (final v in analysis.moduleViolations) (v.sourceFile, v.targetFile),
      for (final v in analysis.workspaceViolations)
        (v.sourceFile, v.targetFile),
    ]) {
      if (!kept.contains(from) || !kept.contains(to)) continue;
      final pair = (group(from), group(to));
      if (pair.$1 != pair.$2) violations[pair] = (violations[pair] ?? 0) + 1;
    }

    final names = groups.keys.toList()..sort();
    final pairs = {...counts.keys, ...violations.keys}.toList()
      ..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    return GroupedGraph(
      groupBy,
      {for (final n in names) n: groups[n]!..sort()},
      [
        for (final pair in pairs)
          GroupEdge(pair.$1, pair.$2, counts[pair] ?? 0, violations[pair] ?? 0),
      ],
    );
  }

  /// The folder [file] is grouped under: the first folder below `lib/`
  /// (`lib/features/cart/a.dart` is `lib/features`), `lib` for a file directly
  /// in it, otherwise the top folder (`bin`), or `.` for a root file.
  static String folderOf(String file) {
    final dirs = file.split('/')..removeLast();
    if (dirs.isEmpty) return '.';
    final lib = dirs.indexOf('lib');
    final end = lib < 0 ? 1 : lib + 2;
    return dirs.take(end > dirs.length ? dirs.length : end).join('/');
  }

  /// JSON form, for the HTML report.
  Map<String, Object> toJson() => {
    'groupBy': groupBy,
    'groups': [
      for (final MapEntry(:key, :value) in groups.entries)
        {'id': key, 'files': value},
    ],
    'edges': [
      for (final e in edges)
        {
          'from': e.from,
          'to': e.to,
          'count': e.count,
          'violations': e.violations,
        },
    ],
  };
}
