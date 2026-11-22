import 'dart:math' as math;

import '../checker/layer_validator.dart';
import '../checker/module_validator.dart';
import '../checker/workspace_validator.dart';
import '../models/config_model.dart';
import '../models/file_metrics.dart';
import '../models/scan_result.dart';

/// Group kinds of a [GraphDiff], in output order: layers, modules and
/// workspace members.
const graphDiffKinds = ['layer', 'module', 'member'];

/// A dependency between two groups that the change adds.
class NewGroupEdge {
  /// One of [graphDiffKinds].
  final String kind;

  /// The importing group.
  final String from;

  /// The imported group.
  final String to;

  /// The imports that create the dependency, sorted by file, then line.
  final List<GraphEdge> imports;

  /// Creates a new group edge.
  const NewGroupEdge(this.kind, this.from, this.to, this.imports);
}

/// An external package that a group starts to import.
class NewGroupPackage {
  /// One of [graphDiffKinds].
  final String kind;

  /// The importing group.
  final String group;

  /// The package name.
  final String package;

  /// Creates a new group package.
  const NewGroupPackage(this.kind, this.group, this.package);
}

/// A file whose fan-in or fan-out grew.
class CouplingGrowth {
  /// The file, present before and after the change.
  final String file;

  /// Fan-in before the change.
  final int fanInBefore;

  /// Fan-in after the change.
  final int fanInAfter;

  /// Fan-out before the change.
  final int fanOutBefore;

  /// Fan-out after the change.
  final int fanOutAfter;

  /// Creates a coupling growth entry.
  const CouplingGrowth({
    required this.file,
    required this.fanInBefore,
    required this.fanInAfter,
    required this.fanOutBefore,
    required this.fanOutAfter,
  });

  /// The larger of the fan-in and fan-out growth.
  int get growth =>
      math.max(fanInAfter - fanInBefore, fanOutAfter - fanOutBefore);
}

/// What a change adds to the architecture: new group-to-group dependencies,
/// new packages per group and coupling growth, compared with a base scan.
/// Advice only; it never fails a run.
class GraphDiff {
  /// Most [coupling] entries kept.
  static const maxCouplingItems = 5;

  /// The base commit the change is compared with.
  final String base;

  /// New dependencies between groups, sorted by kind, then from, then to.
  final List<NewGroupEdge> groupEdges;

  /// New packages per group, sorted by kind, then group, then package.
  final List<NewGroupPackage> packages;

  /// Files whose coupling grew most, at most [maxCouplingItems].
  final List<CouplingGrowth> coupling;

  /// Creates a graph diff.
  const GraphDiff({
    required this.base,
    this.groupEdges = const [],
    this.packages = const [],
    this.coupling = const [],
  });

  /// Whether the change adds nothing.
  bool get isEmpty =>
      groupEdges.isEmpty && packages.isEmpty && coupling.isEmpty;

  /// Compares [before] (the scan of [base]) with [after]. Groups come from
  /// [config] and the workspace members of [after], for both sides.
  static GraphDiff compute({
    required String base,
    required ScanResult before,
    required ScanResult after,
    required ArchGuardConfig config,
  }) {
    final resolvers = <String, String? Function(String)>{
      if (config.layers.isNotEmpty)
        'layer': LayerValidator.layerResolver(config),
      if (config.modules != null)
        'module': () {
          final moduleOf = ModuleValidator.moduleResolver(config);
          return (String f) => moduleOf(f)?.name;
        }(),
      if (after.packages.isNotEmpty)
        'member': () {
          final memberOf = WorkspaceValidator.memberResolver(after.packages);
          return (String f) => memberOf(f)?.name;
        }(),
    };

    final groupEdges = <NewGroupEdge>[];
    final packages = <NewGroupPackage>[];
    for (final kind in graphDiffKinds) {
      final resolve = resolvers[kind];
      if (resolve == null) continue;
      final cache = <String, String?>{};
      String? group(String f) => cache.putIfAbsent(f, () => resolve(f));

      (String, String)? pair(GraphEdge e) {
        final from = group(e.from);
        final to = group(e.to);
        return from == null || to == null || from == to ? null : (from, to);
      }

      final old = {for (final e in before.edges) ?pair(e)};
      final added = <(String, String), List<GraphEdge>>{};
      for (final e in after.edges) {
        final key = pair(e);
        if (key != null && !old.contains(key)) (added[key] ??= []).add(e);
      }
      for (final key in added.keys.toList()..sort(_byPair)) {
        final imports = added[key]!
          ..sort((x, y) {
            final c = x.from.compareTo(y.from);
            return c != 0 ? c : (x.line ?? 0).compareTo(y.line ?? 0);
          });
        groupEdges.add(NewGroupEdge(kind, key.$1, key.$2, imports));
      }

      Set<(String, String)> used(ScanResult s) => {
        for (final i in s.packageImports)
          if (!i.package.startsWith('dart:'))
            if (group(i.file) case final g?) (g, i.package),
      };
      for (final (g, pkg) in used(
        after,
      ).difference(used(before)).toList()..sort(_byPair)) {
        packages.add(NewGroupPackage(kind, g, pkg));
      }
    }

    final was = {for (final m in FileMetrics.compute(before)) m.file: m};
    final coupling =
        [
          for (final m in FileMetrics.compute(after))
            if (was[m.file] case final o?)
              CouplingGrowth(
                file: m.file,
                fanInBefore: o.fanIn,
                fanInAfter: m.fanIn,
                fanOutBefore: o.fanOut,
                fanOutAfter: m.fanOut,
              ),
        ].where((c) => c.growth > 0).toList()..sort((x, y) {
          final c = y.growth.compareTo(x.growth);
          return c != 0 ? c : x.file.compareTo(y.file);
        });

    return GraphDiff(
      base: base,
      groupEdges: groupEdges,
      packages: packages,
      coupling: coupling.take(maxCouplingItems).toList(),
    );
  }

  static int _byPair((String, String) x, (String, String) y) {
    final c = x.$1.compareTo(y.$1);
    return c != 0 ? c : x.$2.compareTo(y.$2);
  }

  /// [scan] with only [files]: other files, the edges touching them and
  /// their package imports are dropped.
  static ScanResult restrictTo(ScanResult scan, Set<String> files) =>
      ScanResult(
        packageName: scan.packageName,
        files: {
          for (final MapEntry(:key, :value) in scan.files.entries)
            if (files.contains(key)) key: value,
        },
        edges: [
          for (final e in scan.edges)
            if (files.contains(e.from) && files.contains(e.to)) e,
        ],
        workspacePackageCount: scan.workspacePackageCount,
        skippedFiles: scan.skippedFiles,
        packageImports: [
          for (final i in scan.packageImports)
            if (files.contains(i.file)) i,
        ],
        packages: scan.packages,
      );

  /// JSON form, under the `diff` key of the JSON export.
  Map<String, Object> toJson() => {
    'base': base,
    'groupEdges': [
      for (final e in groupEdges)
        {
          'kind': e.kind,
          'from': e.from,
          'to': e.to,
          'imports': [
            for (final i in e.imports)
              {'from': i.from, 'line': ?i.line, 'to': i.to},
          ],
        },
    ],
    'packages': [
      for (final p in packages)
        {'kind': p.kind, 'group': p.group, 'package': p.package},
    ],
    'coupling': [
      for (final c in coupling)
        {
          'file': c.file,
          'fanIn': [c.fanInBefore, c.fanInAfter],
          'fanOut': [c.fanOutBefore, c.fanOutAfter],
        },
    ],
  };
}
