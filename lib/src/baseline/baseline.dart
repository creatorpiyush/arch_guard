import 'dart:convert';
import 'dart:io';

import '../checker/layer_validator.dart';
import '../checker/metric_validator.dart';
import '../checker/package_validator.dart';
import '../checker/workspace_validator.dart';
import '../models/cycle.dart';

/// Default baseline file name, resolved relative to the scanned project.
const defaultBaselineFileName = 'arch_guard_baseline.json';

/// A snapshot of known architecture problems that should not fail a run.
///
/// Lets legacy projects adopt arch_guard without fixing everything first:
/// record today's cycles and layer violations once, then fail only on new ones.
class Baseline {
  /// File sets of the circular dependency groups (SCCs) known at capture time.
  final List<Set<String>> cycles;

  /// Known layer violations, keyed by `sourceFile -> targetFile`.
  final Set<String> layerViolations;

  /// Known forbidden-package imports, keyed by `sourceFile -> package`.
  final Set<String> packageViolations;

  /// Known metric limit violations: `file|metric` → value at capture time.
  /// A file whose value grows past this counts as new again (ratchet).
  final Map<String, int> metricViolations;

  /// Known workspace rule violations, keyed by `sourceFile -> targetFile`.
  final Set<String> workspaceViolations;

  /// Creates a baseline holding [cycles], [layerViolations] and
  /// [packageViolations].
  const Baseline({
    this.cycles = const [],
    this.layerViolations = const {},
    this.packageViolations = const {},
    this.metricViolations = const {},
    this.workspaceViolations = const {},
  });

  /// Captures the current problems as a baseline.
  factory Baseline.capture({
    required List<Cycle> cycles,
    required List<LayerViolation> layerViolations,
    List<PackageViolation> packageViolations = const [],
    List<MetricViolation> metricViolations = const [],
    List<WorkspaceViolation> workspaceViolations = const [],
  }) => Baseline(
    cycles: cycles.map((c) => c.files.toSet()).toList(),
    layerViolations: layerViolations.map(violationKey).toSet(),
    packageViolations: packageViolations.map(packageViolationKey).toSet(),
    metricViolations: {for (final v in metricViolations) metricKey(v): v.value},
    workspaceViolations: workspaceViolations.map(workspaceViolationKey).toSet(),
  );

  /// Parses a baseline from its JSON form. Throws [FormatException] if invalid.
  factory Baseline.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('expected a JSON object');
    }
    final version = json['version'];
    if (version != 1) {
      throw FormatException('unsupported baseline version: $version');
    }

    final cycles = <Set<String>>[];
    for (final entry in json['cycles'] as List? ?? const []) {
      final files = (entry as Map)['files'] as List;
      cycles.add(files.cast<String>().toSet());
    }

    final violations = <String>{};
    for (final entry in json['layerViolations'] as List? ?? const []) {
      final map = entry as Map;
      violations.add(
        _key(map['sourceFile'] as String, map['targetFile'] as String),
      );
    }

    final packages = <String>{};
    for (final entry in json['packageViolations'] as List? ?? const []) {
      final map = entry as Map;
      packages.add(_key(map['sourceFile'] as String, map['package'] as String));
    }

    final metrics = <String, int>{};
    for (final entry in json['metricViolations'] as List? ?? const []) {
      final map = entry as Map;
      metrics['${map['file']}|${map['metric']}'] = map['value'] as int;
    }

    final workspace = <String>{};
    for (final entry in json['workspaceViolations'] as List? ?? const []) {
      final map = entry as Map;
      workspace.add(
        _key(map['sourceFile'] as String, map['targetFile'] as String),
      );
    }

    return Baseline(
      cycles: cycles,
      layerViolations: violations,
      packageViolations: packages,
      metricViolations: metrics,
      workspaceViolations: workspace,
    );
  }

  /// Loads the baseline at [path], or returns `null` if the file is missing.
  /// Throws [FormatException] if the file exists but cannot be parsed.
  static Baseline? load(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return Baseline.fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException catch (e) {
      throw FormatException('invalid baseline $path: ${e.message}');
    } on TypeError catch (e) {
      throw FormatException('invalid baseline $path: $e');
    }
  }

  /// Serializes with sorted entries so the file diffs cleanly in review.
  Map<String, dynamic> toJson() {
    final sortedCycles = cycles.map((c) => c.toList()..sort()).toList()
      ..sort((a, b) => a.join('\n').compareTo(b.join('\n')));
    final sortedViolations = layerViolations.toList()..sort();
    return {
      'version': 1,
      'cycles': [
        for (final files in sortedCycles) {'files': files},
      ],
      'layerViolations': [
        for (final key in sortedViolations)
          {
            'sourceFile': key.split(_separator).first,
            'targetFile': key.split(_separator).last,
          },
      ],
      'packageViolations': [
        for (final key in packageViolations.toList()..sort())
          {
            'sourceFile': key.split(_separator).first,
            'package': key.split(_separator).last,
          },
      ],
      'metricViolations': [
        for (final key in metricViolations.keys.toList()..sort())
          {
            'file': key.substring(0, key.lastIndexOf('|')),
            'metric': key.substring(key.lastIndexOf('|') + 1),
            'value': metricViolations[key],
          },
      ],
      'workspaceViolations': [
        for (final key in workspaceViolations.toList()..sort())
          {
            'sourceFile': key.split(_separator).first,
            'targetFile': key.split(_separator).last,
          },
      ],
    };
  }

  /// Writes this baseline to [path] as indented JSON.
  void save(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
    );
  }

  /// Splits current problems into new and already-known ones.
  ///
  /// A cycle is known when all of its files sit inside one baseline cycle, so
  /// a cycle that shrinks stays accepted while one that grows (or merges two
  /// known cycles) counts as new. Only membership is compared: a new import
  /// between files already in one known cycle is not a change.
  BaselineComparison compare({
    required List<Cycle> cycles,
    required List<LayerViolation> layerViolations,
    List<PackageViolation> packageViolations = const [],
    List<MetricViolation> metricViolations = const [],
    List<WorkspaceViolation> workspaceViolations = const [],
  }) {
    final newCycles = <Cycle>[];
    final knownCycles = <Cycle>[];
    final newCycleReasons = <Cycle, String>{};
    final matchedBaselineCycles = <int>{};
    for (final cycle in cycles) {
      final index = this.cycles.indexWhere(
        (known) => known.containsAll(cycle.files),
      );
      if (index == -1) {
        newCycles.add(cycle);
        newCycleReasons[cycle] = _newCycleReason(cycle);
      } else {
        knownCycles.add(cycle);
        matchedBaselineCycles.add(index);
      }
    }

    final newViolations = <LayerViolation>[];
    final knownViolations = <LayerViolation>[];
    final seenViolations = <String>{};
    for (final violation in layerViolations) {
      final key = violationKey(violation);
      if (this.layerViolations.contains(key)) {
        knownViolations.add(violation);
        seenViolations.add(key);
      } else {
        newViolations.add(violation);
      }
    }

    final newPackages = <PackageViolation>[];
    final knownPackages = <PackageViolation>[];
    final seenPackages = <String>{};
    for (final violation in packageViolations) {
      final key = packageViolationKey(violation);
      if (this.packageViolations.contains(key)) {
        knownPackages.add(violation);
        seenPackages.add(key);
      } else {
        newPackages.add(violation);
      }
    }

    final newMetrics = <MetricViolation>[];
    final knownMetrics = <MetricViolation>[];
    final seenMetrics = <String>{};
    for (final violation in metricViolations) {
      final key = metricKey(violation);
      seenMetrics.add(key);
      final known = this.metricViolations[key];
      if (known != null && violation.value <= known) {
        knownMetrics.add(violation);
      } else {
        newMetrics.add(violation);
      }
    }

    final newWorkspace = <WorkspaceViolation>[];
    final knownWorkspace = <WorkspaceViolation>[];
    final seenWorkspace = <String>{};
    for (final violation in workspaceViolations) {
      final key = workspaceViolationKey(violation);
      if (this.workspaceViolations.contains(key)) {
        knownWorkspace.add(violation);
        seenWorkspace.add(key);
      } else {
        newWorkspace.add(violation);
      }
    }

    return BaselineComparison(
      newCycles: newCycles,
      knownCycles: knownCycles,
      newCycleReasons: newCycleReasons,
      newViolations: newViolations,
      knownViolations: knownViolations,
      fixedCycleCount: this.cycles.length - matchedBaselineCycles.length,
      fixedViolationCount: this.layerViolations
          .difference(seenViolations)
          .length,
      newPackageViolations: newPackages,
      knownPackageViolations: knownPackages,
      fixedPackageViolationCount: this.packageViolations
          .difference(seenPackages)
          .length,
      newMetricViolations: newMetrics,
      knownMetricViolations: knownMetrics,
      fixedMetricViolationCount: this.metricViolations.keys
          .toSet()
          .difference(seenMetrics)
          .length,
      newWorkspaceViolations: newWorkspace,
      knownWorkspaceViolations: knownWorkspace,
      fixedWorkspaceViolationCount: this.workspaceViolations
          .difference(seenWorkspace)
          .length,
    );
  }

  /// Why [cycle] fails the membership rule, naming the files it added.
  String _newCycleReason(Cycle cycle) {
    final overlapping = [
      for (final known in cycles)
        if (known.any(cycle.files.contains)) known,
    ];
    if (overlapping.isEmpty) return 'none of its files is in a baseline cycle';
    final added =
        cycle.files
            .where((f) => !overlapping.any((known) => known.contains(f)))
            .toList()
          ..sort();
    final what = overlapping.length == 1
        ? 'grew from a known ${overlapping.single.length}-file cycle'
        : 'merges ${overlapping.length} known cycles';
    return added.isEmpty ? what : '$what, adding ${added.join(', ')}';
  }

  /// Stable identity of a layer violation, independent of layer names and lines.
  static String violationKey(LayerViolation v) =>
      _key(v.sourceFile, v.targetFile);

  /// Stable identity of a forbidden-package import: file and package.
  static String packageViolationKey(PackageViolation v) =>
      _key(v.sourceFile, v.package);

  /// Identity of a metric violation: `file|metric` (the value is compared
  /// separately, so a file that gets worse is new again).
  static String metricKey(MetricViolation v) => '${v.file}|${v.metric}';

  /// Stable identity of a workspace rule violation: importing and imported file.
  static String workspaceViolationKey(WorkspaceViolation v) =>
      _key(v.sourceFile, v.targetFile);

  static const _separator = ' -> ';

  static String _key(String source, String target) =>
      '$source$_separator$target';
}

/// Current problems split into new ones and ones already in the baseline.
class BaselineComparison {
  /// Cycles that are not in the baseline.
  final List<Cycle> newCycles;

  /// Cycles that the baseline already lists.
  final List<Cycle> knownCycles;

  /// Why each of [newCycles] counts as new, e.g.
  /// `grew from a known 3-file cycle, adding lib/d.dart`.
  final Map<Cycle, String> newCycleReasons;

  /// Layer violations that are not in the baseline.
  final List<LayerViolation> newViolations;

  /// Layer violations that the baseline already lists.
  final List<LayerViolation> knownViolations;

  /// Baseline cycles that no longer occur at all.
  final int fixedCycleCount;

  /// Baseline layer violations that no longer occur.
  final int fixedViolationCount;

  /// Forbidden package imports that are not in the baseline.
  final List<PackageViolation> newPackageViolations;

  /// Forbidden package imports that the baseline already lists.
  final List<PackageViolation> knownPackageViolations;

  /// Baseline forbidden package imports that no longer occur.
  final int fixedPackageViolationCount;

  /// Metric violations not in the baseline, or worse than recorded there.
  final List<MetricViolation> newMetricViolations;

  /// Metric violations at or below their baselined value.
  final List<MetricViolation> knownMetricViolations;

  /// Baseline metric violations that no longer occur.
  final int fixedMetricViolationCount;

  /// Workspace rule violations that are not in the baseline.
  final List<WorkspaceViolation> newWorkspaceViolations;

  /// Workspace rule violations that the baseline already lists.
  final List<WorkspaceViolation> knownWorkspaceViolations;

  /// Baseline workspace rule violations that no longer occur.
  final int fixedWorkspaceViolationCount;

  /// Creates a comparison from already split problem lists.
  const BaselineComparison({
    required this.newCycles,
    required this.knownCycles,
    required this.newViolations,
    required this.knownViolations,
    this.newCycleReasons = const {},
    this.fixedCycleCount = 0,
    this.fixedViolationCount = 0,
    this.newPackageViolations = const [],
    this.knownPackageViolations = const [],
    this.fixedPackageViolationCount = 0,
    this.newMetricViolations = const [],
    this.knownMetricViolations = const [],
    this.fixedMetricViolationCount = 0,
    this.newWorkspaceViolations = const [],
    this.knownWorkspaceViolations = const [],
    this.fixedWorkspaceViolationCount = 0,
  });

  /// Treats every problem as new (used when there is no baseline).
  factory BaselineComparison.allNew({
    required List<Cycle> cycles,
    required List<LayerViolation> layerViolations,
    List<PackageViolation> packageViolations = const [],
    List<MetricViolation> metricViolations = const [],
    List<WorkspaceViolation> workspaceViolations = const [],
  }) => BaselineComparison(
    newCycles: cycles,
    knownCycles: const [],
    newViolations: layerViolations,
    knownViolations: const [],
    newPackageViolations: packageViolations,
    newMetricViolations: metricViolations,
    newWorkspaceViolations: workspaceViolations,
  );

  /// Whether [cycle] is new relative to the baseline.
  bool isNewCycle(Cycle cycle) => newCycles.contains(cycle);

  /// Whether [violation] is new relative to the baseline.
  bool isNewViolation(LayerViolation violation) =>
      newViolations.contains(violation);

  /// Whether [violation] is new relative to the baseline.
  bool isNewPackageViolation(PackageViolation violation) =>
      newPackageViolations.contains(violation);

  /// Whether [violation] is new (or worse) relative to the baseline.
  bool isNewMetricViolation(MetricViolation violation) =>
      newMetricViolations.contains(violation);

  /// Whether [violation] is new relative to the baseline.
  bool isNewWorkspaceViolation(WorkspaceViolation violation) =>
      newWorkspaceViolations.contains(violation);
}
