import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../analysis/arch_analysis.dart';
import '../graph/import_path.dart';
import '../scanner/git_changes.dart';
import 'run.dart' show printWarning;

/// Runs `arch_guard why <from> <to> [project_path]`: prints the shortest
/// import path from a file or folder to a file, folder or package. Exits 1
/// when there is none.
Future<int> runWhy(ArgResults args) async {
  final rest = args.rest;
  if (rest.length < 2 || rest.length > 3) {
    stderr.writeln('Usage: arch_guard why <from> <to> [project_path]');
    return 64;
  }
  final absProjectPath = p.canonicalize(rest.length == 3 ? rest[2] : '.');
  if (!Directory(absProjectPath).existsSync()) {
    stderr.writeln(
      'Error: Project directory "$absProjectPath" does not exist.',
    );
    return 2;
  }
  final useColor = args['color'] as bool;

  final ArchAnalysis analysis;
  try {
    analysis = await ArchAnalysis.run(
      projectPath: absProjectPath,
      scanDirs: args['scan-dir'] as List<String>,
      exclude: args['exclude'] as List<String>,
      enableWorkspace: args['workspace'] as bool,
      useBaseline: false,
    );
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 2;
  } on GitException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 2;
  }
  for (final warning in [...analysis.config.warnings, ...analysis.warnings]) {
    printWarning(warning, useColor);
  }

  final scan = analysis.scan;
  final Set<String> from;
  final PathTarget to;
  try {
    from = ImportPath.matchFiles(scan, rest[0]);
    to = ImportPath.matchTarget(scan, rest[1]);
  } on ArgumentError catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 64;
  }

  final path = ImportPath.find(result: scan, from: from, to: to);
  if (path == null) {
    stdout.writeln(
      'No import path from ${rest[0].replaceAll('\\', '/')} to ${to.label}.',
    );
    return 1;
  }

  final cBold = useColor ? '\x1B[1m' : '';
  final cCyan = useColor ? '\x1B[36m' : '';
  final cReset = useColor ? '\x1B[0m' : '';
  if (path.isEmpty) {
    final inside = (from.toList()..sort()).firstWhere(
      (to as FileTarget).files.contains,
    );
    stdout.writeln('$cCyan$inside$cReset is in $cCyan${to.label}$cReset.');
    return 0;
  }
  stdout.writeln(
    '$cBold${path.first.from} reaches ${to.label} in '
    '${path.length} step(s):$cReset',
  );
  for (final step in path) {
    final line = step.line == null ? '' : ':${step.line}';
    final condition = step.condition == null ? '' : '  (if ${step.condition})';
    stdout.writeln(
      '  $cCyan${step.from}$cReset$line  ${step.type}  '
      '$cCyan${step.to}$cReset$condition',
    );
  }
  return 0;
}
