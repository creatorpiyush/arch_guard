import 'package:path/path.dart' as p;

import '../baseline/baseline.dart';
import '../checker/layer_validator.dart';
import '../checker/metric_validator.dart';
import '../checker/package_validator.dart';
import '../checker/workspace_validator.dart';
import '../graph/dependency_graph.dart';
import '../models/config_model.dart';
import '../models/cycle.dart';
import '../models/file_metrics.dart';
import '../models/scan_result.dart';
import '../scanner/git_changes.dart';
import '../scanner/project_scanner.dart';

/// One full arch_guard run: scan, cycles, layer and package rules, baseline.
///
/// The `arch_guard` CLI and `expectArchitecture()` both use this, so a test
/// passes exactly when the CLI would exit with `0`.
class ArchAnalysis {
  /// The scanned files and edges.
  final ScanResult scan;

  /// The configuration in effect (see [ArchGuardConfig.warnings]).
  final ArchGuardConfig config;

  /// The dependency graph built from [scan].
  final DependencyGraph graph;

  /// Every circular dependency group.
  final List<Cycle> cycles;

  /// Every layer violation.
  final List<LayerViolation> layerViolations;

  /// Every forbidden package import.
  final List<PackageViolation> packageViolations;

  /// Fan-in/fan-out for every scanned file, most coupled first.
  final List<FileMetrics> fileMetrics;

  /// Files over a `metrics:` limit.
  final List<MetricViolation> metricViolations;

  /// Imports between workspace members that `workspace_rules` forbids.
  final List<WorkspaceViolation> workspaceViolations;

  /// Problems with the configuration found while analysing (for example
  /// `workspace_rules` in a project that isn't a workspace).
  final List<String> warnings;

  /// Cycles larger than `max_scc_size`.
  final List<Cycle> oversizedCycles;

  /// How the configured layers cover the scanned files.
  final LayerCoverage coverage;

  /// Comparison with the baseline, or `null` when none was used.
  final BaselineComparison? baseline;

  /// Absolute path of the baseline file (whether or not it exists).
  final String baselinePath;

  /// The git ref passed to [run], if any.
  final String? since;

  /// Files changed since [since], or `null` for a full run. When set, every
  /// problem list holds only problems touching one of these files.
  final Set<String>? changedFiles;

  /// Creates an analysis from already computed parts; usually built by [run].
  const ArchAnalysis({
    required this.scan,
    required this.config,
    required this.graph,
    required this.cycles,
    required this.layerViolations,
    required this.packageViolations,
    required this.oversizedCycles,
    this.fileMetrics = const [],
    this.metricViolations = const [],
    this.workspaceViolations = const [],
    this.warnings = const [],
    required this.coverage,
    required this.baselinePath,
    this.baseline,
    this.since,
    this.changedFiles,
  });

  /// Cycles not in the baseline (all of them without a baseline).
  List<Cycle> get newCycles => baseline?.newCycles ?? cycles;

  /// Layer violations not in the baseline.
  List<LayerViolation> get newLayerViolations =>
      baseline?.newViolations ?? layerViolations;

  /// Forbidden package imports not in the baseline.
  List<PackageViolation> get newPackageViolations =>
      baseline?.newPackageViolations ?? packageViolations;

  /// Metric violations not in the baseline, or worse than recorded there.
  List<MetricViolation> get newMetricViolations =>
      baseline?.newMetricViolations ?? metricViolations;

  /// The `metrics: hotspots` most coupled files (files with no edges skipped).
  List<FileMetrics> get hotspots => fileMetrics
      .where((m) => m.coupling > 0)
      .take(config.hotspotCount)
      .toList();

  /// Workspace rule violations not in the baseline.
  List<WorkspaceViolation> get newWorkspaceViolations =>
      baseline?.newWorkspaceViolations ?? workspaceViolations;

  /// Oversized cycles that are also new.
  List<Cycle> get newOversizedCycles =>
      oversizedCycles.where(newCycles.contains).toList();

  /// One line per problem that fails the run; empty means it passes.
  ///
  /// Mirrors the CLI: layer violations count only with
  /// `fail_on_layer_violation: true`, cycles only with [failOnCycle], and
  /// forbidden packages and `max_scc_size` always.
  List<String> failures({bool failOnCycle = true}) {
    String at(String file, int? line) => line == null ? file : '$file:$line';
    return [
      for (final v in newPackageViolations)
        'Forbidden package: ${at(v.sourceFile, v.line)} imports ${v.uri}. '
            '${v.rule}',
      for (final v in newMetricViolations) 'Metric limit: ${v.rule}',
      for (final v in newWorkspaceViolations)
        'Workspace rule: ${at(v.sourceFile, v.line)} imports ${v.targetFile}. '
            '${v.rule}',
      if (config.failOnLayerViolation)
        for (final v in newLayerViolations)
          'Layer violation: ${at(v.sourceFile, v.line)} '
              '(${v.sourceLayer}) imports ${v.targetFile} '
              '(${v.targetLayer}). ${v.rule}',
      for (final c in newOversizedCycles)
        'Too large: a circular dependency group has ${c.files.length} files '
            '(max_scc_size: ${config.maxSccSize}).',
      if (failOnCycle)
        for (final c in newCycles)
          'Circular dependency: ${c.exampleChain.join(' -> ')}',
    ];
  }

  /// Scans [projectPath] and checks it against its arch_guard configuration.
  ///
  /// [baselinePath] is resolved against [projectPath] unless absolute.
  /// Throws [FormatException] if [useBaseline] is set and the baseline file
  /// exists but is invalid.
  ///
  /// With [since] (a git ref such as `origin/main`), the whole project is
  /// still analysed, but only problems touching files changed since the merge
  /// base with [since] are kept; the baseline's fixed counts still come from
  /// the full run. Throws [GitException] when git fails.
  static Future<ArchAnalysis> run({
    String projectPath = '.',
    List<String> scanDirs = const ['lib'],
    List<String> exclude = const [],
    bool enableWorkspace = true,
    String baselinePath = defaultBaselineFileName,
    bool useBaseline = true,
    String? since,
  }) async {
    final root = p.canonicalize(projectPath);
    // Ask git first: a bad ref should fail before the (slow) scan.
    final changed = since == null
        ? null
        : GitChanges.since(since, projectRoot: root);
    final config = ArchGuardConfig.load(root);
    final scan = await ProjectScanner(
      rootPath: root,
      scanDirs: scanDirs,
      exclude: [...exclude, ...config.ignorePatterns],
      enableWorkspace: enableWorkspace,
    ).scan();
    final graph = DependencyGraph.fromScanResult(scan);
    final cycles = graph.findCircularDependencies();
    final layerViolations = LayerValidator.validate(
      result: scan,
      config: config,
    );
    final packageViolations = PackageValidator.validate(
      result: scan,
      config: config,
    );
    final fileMetrics = FileMetrics.compute(scan);
    final metricViolations = MetricValidator.validate(
      metrics: fileMetrics,
      config: config,
    );
    final workspaceViolations = WorkspaceValidator.validate(
      result: scan,
      config: config,
    );
    final warnings = <String>[
      if (config.workspaceRules.isNotEmpty && scan.packages.isEmpty)
        'workspace_rules is ignored: this project is not a workspace.',
      if (scan.packages.isNotEmpty)
        for (final pattern in WorkspaceValidator.unmatchedPatterns(
          result: scan,
          config: config,
        ))
          'workspace_rules: `$pattern` matches no workspace member.',
    ];
    final maxScc = config.maxSccSize;
    final absBaseline = p.isAbsolute(baselinePath)
        ? baselinePath
        : p.join(root, baselinePath);
    final baseline = useBaseline ? Baseline.load(absBaseline) : null;

    final oversized = maxScc == null
        ? const <Cycle>[]
        : cycles.where((c) => c.files.length > maxScc).toList();
    final comparison = baseline?.compare(
      cycles: cycles,
      layerViolations: layerViolations,
      packageViolations: packageViolations,
      metricViolations: metricViolations,
      workspaceViolations: workspaceViolations,
    );

    // Without --since every predicate is true; with it, keep only problems
    // whose importing file (or, for cycles, any member) changed. The
    // comparison was made on the full lists, so its fixed counts stay right.
    bool touches(String file) => changed == null || changed.contains(file);
    bool cycleTouches(Cycle c) => c.files.any(touches);
    List<Cycle> cyc(List<Cycle> l) => l.where(cycleTouches).toList();
    List<LayerViolation> lay(List<LayerViolation> l) =>
        l.where((v) => touches(v.sourceFile)).toList();
    List<PackageViolation> pkg(List<PackageViolation> l) =>
        l.where((v) => touches(v.sourceFile)).toList();
    // A file goes over max_fan_in because another file starts importing it.
    final importedByChanged = {
      for (final e in scan.edges)
        if (touches(e.from)) e.to,
    };
    List<MetricViolation> met(List<MetricViolation> l) => l
        .where(
          (v) =>
              touches(v.file) ||
              (v.metric == 'fan_in' && importedByChanged.contains(v.file)),
        )
        .toList();
    List<WorkspaceViolation> ws(List<WorkspaceViolation> l) =>
        l.where((v) => touches(v.sourceFile)).toList();

    return ArchAnalysis(
      scan: scan,
      config: config,
      graph: graph,
      cycles: cyc(cycles),
      layerViolations: lay(layerViolations),
      packageViolations: pkg(packageViolations),
      fileMetrics: fileMetrics,
      metricViolations: met(metricViolations),
      workspaceViolations: ws(workspaceViolations),
      warnings: warnings,
      oversizedCycles: cyc(oversized),
      coverage: LayerValidator.coverage(result: scan, config: config),
      baselinePath: absBaseline,
      since: since,
      changedFiles: changed,
      baseline: comparison == null
          ? null
          : BaselineComparison(
              newCycles: cyc(comparison.newCycles),
              knownCycles: cyc(comparison.knownCycles),
              newViolations: lay(comparison.newViolations),
              knownViolations: lay(comparison.knownViolations),
              newPackageViolations: pkg(comparison.newPackageViolations),
              knownPackageViolations: pkg(comparison.knownPackageViolations),
              newMetricViolations: met(comparison.newMetricViolations),
              knownMetricViolations: met(comparison.knownMetricViolations),
              newWorkspaceViolations: ws(comparison.newWorkspaceViolations),
              knownWorkspaceViolations: ws(comparison.knownWorkspaceViolations),
              fixedCycleCount: comparison.fixedCycleCount,
              fixedViolationCount: comparison.fixedViolationCount,
              fixedPackageViolationCount: comparison.fixedPackageViolationCount,
              fixedMetricViolationCount: comparison.fixedMetricViolationCount,
              fixedWorkspaceViolationCount:
                  comparison.fixedWorkspaceViolationCount,
            ),
    );
  }
}
