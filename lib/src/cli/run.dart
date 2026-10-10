import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../analysis/arch_analysis.dart';
import '../baseline/baseline.dart';
import '../exporters/dot_exporter.dart';
import '../exporters/html_exporter.dart';
import '../exporters/json_exporter.dart';
import '../exporters/markdown_exporter.dart';
import '../exporters/mermaid_exporter.dart';
import '../exporters/sarif_exporter.dart';
import '../graph/dependency_explainer.dart';
import '../reporters/text_reporter.dart';
import '../version.dart';
import 'args_config.dart';
import 'init_command.dart';

/// Entry point logic for CLI execution.
Future<int> runCli(List<String> args) async {
  final parser = ArgsConfig.buildParser();

  ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln(
      args.isNotEmpty && args.first == 'init'
          ? ArgsConfig.buildInitParser().usage
          : parser.usage,
    );
    return 64; // Sysexit code for command-line usage error
  }

  final command = argResults.command;
  if (command?.name == 'init') {
    if (command!['help'] == true) {
      stdout.writeln('Usage: arch_guard init [project_path] [options]');
      stdout.writeln();
      stdout.writeln(
        'Detects the project layout and writes a starter arch_guard.yaml.',
      );
      stdout.writeln();
      stdout.writeln(ArgsConfig.buildInitParser().usage);
      return 0;
    }
    return runInit(command);
  }

  if (argResults['help'] == true) {
    stdout.writeln('Usage: arch_guard [project_path] [options]');
    stdout.writeln('       arch_guard init [project_path] [--preset <name>]');
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

  ArchAnalysis analysis;
  try {
    analysis = await ArchAnalysis.run(
      projectPath: absProjectPath,
      scanDirs: scanDirs,
      exclude: excludes,
      enableWorkspace: enableWorkspace,
      baselinePath: argResults['baseline'] as String,
      // --explain doesn't need the baseline, and --update-baseline must
      // work even when the existing file is broken.
      useBaseline: !updateBaseline && (explainTarget?.isEmpty ?? true),
    );
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 2;
  }
  final config = analysis.config;
  for (final warning in config.warnings) {
    _warn(warning, useColor);
  }
  final scanResult = analysis.scan;
  final graph = analysis.graph;
  final cycles = analysis.cycles;
  final layerViolations = analysis.layerViolations;
  final packageViolations = analysis.packageViolations;
  final comparison = analysis.baseline;
  final baselinePath = analysis.baselinePath;
  final newCycles = analysis.newCycles;
  final newViolations = analysis.newLayerViolations;
  final newPackageViolations = analysis.newPackageViolations;

  scanResult.skippedFiles.forEach((file, reason) {
    _warn('could not read $file: $reason', useColor);
  });

  final coverage = analysis.coverage;
  for (final layer in coverage.emptyLayers.where(
    (l) => !config.presetOnlyLayers.contains(l),
  )) {
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

  final cRed = useColor ? '\x1B[31m' : '';
  final cGreen = useColor ? '\x1B[32m' : '';
  final cReset = useColor ? '\x1B[0m' : '';

  // Text summary report is always printed to terminal
  final textReporter = TextReporter(useColor: useColor);
  stdout.write(textReporter.formatReport(result: scanResult, cycles: cycles));

  if (newViolations.isNotEmpty) {
    final label = comparison == null ? '' : 'NEW ';
    stdout.writeln(
      '$cRed[!] ${label}LAYER BOUNDARY VIOLATIONS DETECTED (${newViolations.length}):$cReset',
    );
    final cDim = useColor ? '\x1B[2m' : '';
    for (final v in newViolations) {
      stdout.writeln('  $v');
      stdout.writeln('     ${cDim}Rule: ${v.rule}$cReset');
    }
    final configName = config.sourcePath == null
        ? 'arch_guard.yaml'
        : p.basename(config.sourcePath!);
    stdout.writeln();
    stdout.writeln(
      '  How to fix: invert the dependency (an interface in the importing '
      'layer, implemented by the imported one), move the code to a layer it '
      'may import, or, if the dependency is intended, add the layer to '
      '`allowed_imports` in $configName.',
    );
    if (config.preset != null) {
      stdout.writeln(
        '  (Using preset `${config.preset}`: to change a layer\'s rules, list '
        'it under `layers:` with only the keys to change, e.g. '
        '`allowed_imports`.)',
      );
    }
    stdout.writeln();
  }

  if (newPackageViolations.isNotEmpty) {
    final label = comparison == null ? '' : 'NEW ';
    final cDim = useColor ? '\x1B[2m' : '';
    stdout.writeln(
      '$cRed[!] ${label}FORBIDDEN PACKAGE IMPORTS '
      '(${newPackageViolations.length}):$cReset',
    );
    for (final v in newPackageViolations) {
      stdout.writeln('  $v');
      stdout.writeln('     ${cDim}Rule: ${v.rule}$cReset');
    }
    stdout.writeln();
    stdout.writeln(
      '  How to fix: depend on an interface in the importing layer and '
      'implement it where the package is allowed, or remove the entry from '
      '`forbidden_packages`.',
    );
    stdout.writeln();
  }

  final maxSccSize = config.maxSccSize;
  final oversizedSccs = analysis.oversizedCycles;
  final newOversizedSccs = analysis.newOversizedCycles;

  if (comparison != null) {
    stdout.writeln(
      'Baseline: ${p.relative(baselinePath, from: absProjectPath)}',
    );
    stdout.writeln(
      '  Known (ignored): ${comparison.knownCycles.length} cycle group(s), '
      '${comparison.knownViolations.length} layer violation(s), '
      '${comparison.knownPackageViolations.length} forbidden package '
      'import(s)',
    );
    final newColor =
        newCycles.isEmpty &&
            newViolations.isEmpty &&
            newPackageViolations.isEmpty
        ? cGreen
        : cRed;
    stdout.writeln(
      '  New:             $newColor${newCycles.length} cycle group(s), '
      '${newViolations.length} layer violation(s), '
      '${newPackageViolations.length} forbidden package import(s)$cReset',
    );
    for (final cycle in newCycles) {
      final id = cycle.scc?.id;
      stdout.writeln(
        '    New cycle${id != null ? ' #$id' : ''}: '
        '${cycle.exampleChain.join(' -> ')}',
      );
    }
    if (comparison.fixedCycleCount > 0 ||
        comparison.fixedViolationCount > 0 ||
        comparison.fixedPackageViolationCount > 0) {
      stdout.writeln(
        '  $cGreen${comparison.fixedCycleCount} cycle group(s), '
        '${comparison.fixedViolationCount} layer violation(s) and '
        '${comparison.fixedPackageViolationCount} forbidden package '
        'import(s) in the baseline are fixed.$cReset Run with --update-baseline to lock this in.',
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
        packageViolations: packageViolations.map((v) => v.toJson()).toList(),
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
        packageViolations: packageViolations,
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
        packageViolations: packageViolations,
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
      packageViolations: packageViolations,
    ).save(baselinePath);
    stdout.writeln(
      '${cGreen}Baseline written to $baselinePath$cReset '
      '(${cycles.length} cycle group(s), ${layerViolations.length} layer '
      'violation(s), ${packageViolations.length} forbidden package '
      'import(s)). Commit it; later runs fail only on new problems.',
    );
    return 0;
  }

  if (newPackageViolations.isNotEmpty) {
    return 1;
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
