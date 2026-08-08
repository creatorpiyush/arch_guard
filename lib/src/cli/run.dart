import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../checker/layer_validator.dart';
import '../exporters/dot_exporter.dart';
import '../exporters/html_exporter.dart';
import '../exporters/json_exporter.dart';
import '../exporters/mermaid_exporter.dart';
import '../graph/dependency_explainer.dart';
import '../graph/dependency_graph.dart';
import '../models/config_model.dart';
import '../reporters/text_reporter.dart';
import '../scanner/project_scanner.dart';
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

  // Load arch_guard.yaml / dep_graph.yaml / pubspec.yaml layer rules & ignores
  final config = DepGraphConfig.load(absProjectPath);
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

  // Text summary report is always printed to terminal
  final textReporter = TextReporter(useColor: useColor);
  stdout.write(textReporter.formatReport(result: scanResult, cycles: cycles));

  if (layerViolations.isNotEmpty) {
    final cRed = useColor ? '\x1B[31m' : '';
    final cReset = useColor ? '\x1B[0m' : '';
    stdout.writeln(
      '$cRed[!] LAYER BOUNDARY VIOLATIONS DETECTED (${layerViolations.length}):$cReset',
    );
    for (final v in layerViolations) {
      stdout.writeln('  $v');
    }
    stdout.writeln();
  }

  final exportAll = formats.contains('all');

  if (exportAll ||
      formats.contains('dot') ||
      formats.contains('html') ||
      formats.contains('json') ||
      formats.contains('mermaid')) {
    final absOutputDir = p.isAbsolute(outputDir)
        ? outputDir
        : p.join(absProjectPath, outputDir);

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
    stdout.writeln();
  }

  if (layerViolations.isNotEmpty && config.failOnLayerViolation) {
    return 1;
  }

  if (cycles.isNotEmpty && failOnCycle) {
    return 1;
  }

  return 0;
}
