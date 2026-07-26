import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../exporters/dot_exporter.dart';
import '../exporters/html_exporter.dart';
import '../graph/dependency_graph.dart';
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
    stdout.writeln('Usage: dep_graph_visualizer [project_path] [options]');
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
  final scanDirs = argResults['scan-dir'] as List<String>;
  final excludes = argResults['exclude'] as List<String>;
  final useColor = argResults['color'] as bool;
  final failOnCycle = argResults['fail-on-cycle'] as bool;
  final enableWorkspace = argResults['workspace'] as bool;

  final scanner = ProjectScanner(
    rootPath: absProjectPath,
    scanDirs: scanDirs,
    exclude: excludes,
    enableWorkspace: enableWorkspace,
  );

  final scanResult = await scanner.scan();
  final graph = DependencyGraph.fromScanResult(scanResult);
  final cycles = graph.findCircularDependencies();

  // Text summary report is always printed to terminal
  final textReporter = TextReporter(useColor: useColor);
  stdout.write(textReporter.formatReport(result: scanResult, cycles: cycles));

  final exportAll = formats.contains('all');

  if (exportAll || formats.contains('dot') || formats.contains('html')) {
    final absOutputDir = p.isAbsolute(outputDir)
        ? outputDir
        : p.join(absProjectPath, outputDir);

    final outDir = Directory(absOutputDir);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    if (exportAll || formats.contains('dot')) {
      final dotPath = p.join(absOutputDir, 'dependency_graph.dot');
      final dotContent = DotExporter.export(result: scanResult, cycles: cycles);
      File(dotPath).writeAsStringSync(dotContent);
      stdout.writeln('Exported DOT graph to: $dotPath');
    }

    if (exportAll || formats.contains('html')) {
      final htmlPath = p.join(absOutputDir, 'dependency_graph.html');
      final htmlContent = HtmlExporter.export(
        result: scanResult,
        cycles: cycles,
      );
      File(htmlPath).writeAsStringSync(htmlContent);
      stdout.writeln('Exported interactive HTML visualizer to: $htmlPath');
    }
    stdout.writeln();
  }

  if (cycles.isNotEmpty && failOnCycle) {
    return 1;
  }

  return 0;
}
