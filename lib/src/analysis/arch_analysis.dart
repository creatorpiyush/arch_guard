import 'package:path/path.dart' as p;

import '../baseline/baseline.dart';
import '../checker/layer_validator.dart';
import '../checker/metric_validator.dart';
import '../checker/package_validator.dart';
import '../graph/dependency_graph.dart';
import '../models/config_model.dart';
import '../models/cycle.dart';
import '../models/file_metrics.dart';
import '../models/scan_result.dart';
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

  /// Cycles larger than `max_scc_size`.
  final List<Cycle> oversizedCycles;

  /// How the configured layers cover the scanned files.
  final LayerCoverage coverage;

  /// Comparison with the baseline, or `null` when none was used.
  final BaselineComparison? baseline;

  /// Absolute path of the baseline file (whether or not it exists).
  final String baselinePath;

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
    required this.coverage,
    required this.baselinePath,
    this.baseline,
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
  static Future<ArchAnalysis> run({
    String projectPath = '.',
    List<String> scanDirs = const ['lib'],
    List<String> exclude = const [],
    bool enableWorkspace = true,
    String baselinePath = defaultBaselineFileName,
    bool useBaseline = true,
  }) async {
    final root = p.canonicalize(projectPath);
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
    final maxScc = config.maxSccSize;
    final absBaseline = p.isAbsolute(baselinePath)
        ? baselinePath
        : p.join(root, baselinePath);
    final baseline = useBaseline ? Baseline.load(absBaseline) : null;

    return ArchAnalysis(
      scan: scan,
      config: config,
      graph: graph,
      cycles: cycles,
      layerViolations: layerViolations,
      packageViolations: packageViolations,
      fileMetrics: fileMetrics,
      metricViolations: metricViolations,
      oversizedCycles: maxScc == null
          ? const []
          : cycles.where((c) => c.files.length > maxScc).toList(),
      coverage: LayerValidator.coverage(result: scan, config: config),
      baselinePath: absBaseline,
      baseline: baseline?.compare(
        cycles: cycles,
        layerViolations: layerViolations,
        packageViolations: packageViolations,
        metricViolations: metricViolations,
      ),
    );
  }
}
