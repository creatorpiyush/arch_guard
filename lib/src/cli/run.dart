import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../baseline/baseline.dart';
import '../checker/layer_validator.dart';
import '../exporters/dot_exporter.dart';
import '../exporters/html_exporter.dart';
import '../exporters/json_exporter.dart';
import '../exporters/markdown_exporter.dart';
import '../exporters/mermaid_exporter.dart';
import '../exporters/sarif_exporter.dart';
import '../graph/dependency_explainer.dart';
import '../graph/dependency_graph.dart';
import '../models/config_model.dart';
import '../models/cycle.dart';
import '../reporters/text_reporter.dart';
import '../scanner/project_scanner.dart';
import '../version.dart';
import 'args_config.dart';

/// Entry point logic for CLI execution.
Future<int> runCli(List<String> args) async {
  final parser = ArgsConfig.buildParser();

  ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln(parser.usage);
    return 64; // Sysexit code for command-line usage error
  }

  if (argResults['help'] == true) {
    stdout.writeln('Usage: arch_guard [project_path] [options]');
    stdout.writeln();
    stdout.writeln(parser.usage);
    return 0;
  }

  if (argResults['version'] == true) {
    stdout.writeln('arch_guard $packageVersion');
    return 0;
  }

  final rest = argResults.rest;
  final projectPath = rest.isNotEmpty ? rest.first : '.';
  final absProjectPath = p.canonicalize(projectPath);

  if (!Directory(absProjectPath).existsSync()) {
    stderr.writeln(
      'Error: Project directory "$absProjectPath" does not exist.',
    );
    return 2;
  }

  final formats = (argResults['format'] as List<String>).toSet();
  final outputDir = argResults['output'] as String;
  final scope = argResults['scope'] as String;
  final explainTarget = argResults['explain'] as String?;
  final scanDirs = argResults['scan-dir'] as List<String>;
  final excludes = argResults['exclude'] as List<String>;
  final useColor = argResults['color'] as bool;
  final offline = argResults['offline'] as bool;
  final failOnCycle = argResults['fail-on-cycle'] as bool;
  final enableWorkspace = argResults['workspace'] as bool;
  final updateBaseline = argResults['update-baseline'] as bool;
  final baselinePath = _resolve(
    absProjectPath,
    argResults['baseline'] as String,
  );

  // Load arch_guard.yaml / dep_graph.yaml / pubspec.yaml layer rules & ignores
  final config = ArchGuardConfig.load(absProjectPath);
  for (final warning in config.warnings) {
    _warn(warning, useColor);
  }
  final mergedExcludes = [...excludes, ...config.ignorePatterns];

  final scanner = ProjectScanner(
    rootPath: absProjectPath,
    scanDirs: scanDirs,
    exclude: mergedExcludes,
    enableWorkspace: enableWorkspace,
  );

  final scanResult = await scanner.scan();
  final graph = DependencyGraph.fromScanResult(scanResult);
  final cycles = graph.findCircularDependencies();
  final layerViolations = LayerValidator.validate(
    result: scanResult,
    config: config,
  );

  scanResult.skippedFiles.forEach((file, reason) {
    _warn('could not read $file: $reason', useColor);
  });

  final coverage = LayerValidator.coverage(result: scanResult, config: config);
  for (final layer in coverage.emptyLayers) {
    _warn(
      'layer `$layer` matched no scanned files; check its patterns.',
      useColor,
    );
  }
  if (coverage.unassignedFiles.isNotEmpty) {
    const previewCount = 5;
    final preview = coverage.unassignedFiles.take(previewCount).join(', ');
    final more = coverage.unassignedFiles.length > previewCount
        ? ', ... (+${coverage.unassignedFiles.length - previewCount} more)'
        : '';
    _warn(
      '${coverage.unassignedFiles.length} file(s) belong to no layer and are '
      'not checked for layer violations: $preview$more',
      useColor,
    );
  }

  // If explain target is specified, print explanation and exit
  if (explainTarget != null && explainTarget.isNotEmpty) {
    stdout.write(
      DependencyExplainer.explainFile(
        targetFile: explainTarget,
        graph: graph,
        cycles: cycles,
        color: useColor,
      ),
    );
    return 0;
  }

  Baseline? baseline;
  if (!updateBaseline) {
    try {
      baseline = Baseline.load(baselinePath);
    } on FormatException catch (e) {
      stderr.writeln('Error: ${e.message}');
      return 2;
    }
  }
  final comparison = baseline?.compare(
    cycles: cycles,
    layerViolations: layerViolations,
  );
  final newCycles = comparison?.newCycles ?? cycles;
  final newViolations = comparison?.newViolations ?? layerViolations;

  final cRed = useColor ? '\x1B[31m' : '';
  final cGreen = useColor ? '\x1B[32m' : '';
  final cReset = useColor ? '\x1B[0m' : '';

  // Text summary report is always printed to terminal
  final textReporter = TextReporter(useColor: useColor);
  stdout.write(textReporter.formatReport(result: scanResult, cycles: cycles));

  if (newViolations.isNotEmpty) {
    final label = baseline == null ? '' : 'NEW ';
    stdout.writeln(
      '$cRed[!] ${label}LAYER BOUNDARY VIOLATIONS DETECTED (${newViolations.length}):$cReset',
    );
    for (final v in newViolations) {
      stdout.writeln('  $v');
    }
    stdout.writeln();
  }

  final maxSccSize = config.maxSccSize;
  final oversizedSccs = maxSccSize == null
      ? const <Cycle>[]
      : cycles.where((c) => c.files.length > maxSccSize).toList();
  final newOversizedSccs = oversizedSccs.where(newCycles.contains).toList();

  if (comparison != null) {
    stdout.writeln(
      'Baseline: ${p.relative(baselinePath, from: absProjectPath)}',
    );
    stdout.writeln(
      '  Known (ignored): ${comparison.knownCycles.length} cycle group(s), '
      '${comparison.knownViolations.length} layer violation(s)',
    );
    final newColor = newCycles.isEmpty && newViolations.isEmpty ? cGreen : cRed;
    stdout.writeln(
      '  New:             $newColor${newCycles.length} cycle group(s), '
      '${newViolations.length} layer violation(s)$cReset',
    );
    for (final cycle in newCycles) {
      final id = cycle.scc?.id;
      stdout.writeln(
        '    New cycle${id != null ? ' #$id' : ''}: '
        '${cycle.exampleChain.join(' -> ')}',
      );
    }
    if (comparison.fixedCycleCount > 0 || comparison.fixedViolationCount > 0) {
      stdout.writeln(
        '  $cGreen${comparison.fixedCycleCount} cycle group(s) and '
        '${comparison.fixedViolationCount} layer violation(s) in the '
        'baseline are fixed.$cReset Run with --update-baseline to lock this in.',
      );
    }
    stdout.writeln();
  }

  final exportAll = formats.contains('all');

  if (exportAll || formats.any((f) => f != 'text')) {
    final absOutputDir = _resolve(absProjectPath, outputDir);

    final outDir = Directory(absOutputDir);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    if (exportAll || formats.contains('dot')) {
      final dotPath = p.join(absOutputDir, 'dependency_graph.dot');
      final dotContent = DotExporter.export(
        result: scanResult,
        cycles: cycles,
        scope: scope,
      );
      File(dotPath).writeAsStringSync(dotContent);
      stdout.writeln('Exported DOT graph to: $dotPath');
    }

    if (exportAll || formats.contains('html')) {
      final htmlPath = p.join(absOutputDir, 'dependency_graph.html');
      final htmlContent = HtmlExporter.export(
        result: scanResult,
        cycles: cycles,
        scope: scope,
        offline: offline,
      );
      File(htmlPath).writeAsStringSync(htmlContent);
      stdout.writeln('Exported interactive HTML visualizer to: $htmlPath');
    }

    if (exportAll || formats.contains('json')) {
      final jsonPath = p.join(absOutputDir, 'dependency_graph.json');
      final jsonContent = JsonExporter.export(
        result: scanResult,
        cycles: cycles,
        layerViolations: layerViolations.map((v) => v.toJson()).toList(),
      );
      File(jsonPath).writeAsStringSync(jsonContent);
      stdout.writeln('Exported JSON data report to: $jsonPath');
    }

    if (exportAll || formats.contains('mermaid')) {
      final mermaidPath = p.join(absOutputDir, 'dependency_graph.mmd');
      final mermaidContent = MermaidExporter.export(
        result: scanResult,
        cycles: cycles,
        scope: scope,
      );
      File(mermaidPath).writeAsStringSync(mermaidContent);
      stdout.writeln('Exported Mermaid diagram to: $mermaidPath');
    }

    if (exportAll || formats.contains('sarif')) {
      final sarifPath = p.join(absOutputDir, 'arch_guard.sarif');
      final sarifContent = SarifExporter.export(
        result: scanResult,
        cycles: cycles,
        layerViolations: layerViolations,
        baseline: comparison,
        oversizedCycles: oversizedSccs,
        maxSccSize: maxSccSize,
        failOnCycle: failOnCycle,
        failOnLayerViolation: config.failOnLayerViolation,
        uriPrefix: _repoRelativePrefix(absProjectPath),
      );
      File(sarifPath).writeAsStringSync(sarifContent);
      stdout.writeln('Exported SARIF report to: $sarifPath');
    }

    if (exportAll || formats.contains('markdown')) {
      final markdownPath = p.join(absOutputDir, 'arch_guard_report.md');
      final markdownContent = MarkdownExporter.export(
        result: scanResult,
        cycles: cycles,
        layerViolations: layerViolations,
        baseline: comparison,
        oversizedCycles: oversizedSccs,
        maxSccSize: maxSccSize,
      );
      File(markdownPath).writeAsStringSync(markdownContent);
      stdout.writeln('Exported Markdown summary to: $markdownPath');
    }
    stdout.writeln();
  }

  if (newOversizedSccs.isNotEmpty) {
    stdout.writeln(
      '$cRed[!] SCC SIZE LIMIT EXCEEDED (max_scc_size: $maxSccSize):$cReset',
    );
    for (final cycle in newOversizedSccs) {
      final id = cycle.scc?.id;
      stdout.writeln(
        '  Component${id != null ? ' #$id' : ''} has ${cycle.files.length} files',
      );
    }
    stdout.writeln();
  }

  if (updateBaseline) {
    Baseline.capture(
      cycles: cycles,
      layerViolations: layerViolations,
    ).save(baselinePath);
    stdout.writeln(
      '${cGreen}Baseline written to $baselinePath$cReset '
      '(${cycles.length} cycle group(s), ${layerViolations.length} layer '
      'violation(s)). Commit it; later runs fail only on new problems.',
    );
    return 0;
  }

  if (newViolations.isNotEmpty && config.failOnLayerViolation) {
    return 1;
  }

  if (newOversizedSccs.isNotEmpty) {
    return 1;
  }

  if (newCycles.isNotEmpty && failOnCycle) {
    return 1;
  }

  return 0;
}

/// Resolves [path] against the scanned project unless it is absolute.
String _resolve(String absProjectPath, String path) =>
    p.isAbsolute(path) ? path : p.join(absProjectPath, path);

/// Path of [absProjectPath] inside its git repository (e.g. `packages/app/`),
/// so SARIF locations resolve from the repository root. Empty when the
/// project is the repository root or not inside a git repository.
String _repoRelativePrefix(String absProjectPath) {
  var dir = Directory(absProjectPath);
  while (true) {
    final git = p.join(dir.path, '.git');
    if (FileSystemEntity.typeSync(git) != FileSystemEntityType.notFound) {
      final rel = p.relative(absProjectPath, from: dir.path);
      return rel == '.' ? '' : '${p.split(rel).join('/')}/';
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return '';
    dir = parent;
  }
}

void _warn(String message, bool useColor) {
  final cYellow = useColor ? '\x1B[33m' : '';
  final cReset = useColor ? '\x1B[0m' : '';
  stderr.writeln('${cYellow}Warning:$cReset $message');
}
