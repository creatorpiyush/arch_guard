import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../graph/affected_files.dart';
import '../scanner/git_changes.dart';
import '../scanner/project_scanner.dart';

const _scanDirs = ['lib', 'test', 'integration_test'];

/// Runs `arch_guard affected`: prints the tests, files or packages that the
/// files changed since `--since` can affect, one per line on stdout.
Future<int> runAffected(ArgResults args) async {
  final since = args['since'] as String?;
  if (since == null) {
    stderr.writeln('Error: affected needs --since <git-ref>.');
    return 64;
  }
  final projectPath = args.rest.isNotEmpty ? args.rest.first : '.';
  final absProjectPath = p.canonicalize(projectPath);
  if (!Directory(absProjectPath).existsSync()) {
    stderr.writeln(
      'Error: Project directory "$absProjectPath" does not exist.',
    );
    return 2;
  }

  final AffectedResult result;
  final Set<String> changed;
  try {
    changed = GitChanges.since(since, projectRoot: absProjectPath);
    final scan = await ProjectScanner(
      rootPath: absProjectPath,
      scanDirs: _scanDirs,
      memberScanDirs: _scanDirs,
      exclude: args['exclude'] as List<String>,
      enableWorkspace: args['workspace'] as bool,
    ).scan();
    result = AffectedFiles.find(result: scan, changed: changed);
  } on GitException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 2;
  } on FileSystemException catch (e) {
    stderr.writeln('Error: ${e.message}: ${e.path}');
    return 2;
  }

  if (args['json'] as bool) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'since': since,
        'changedFiles': changed.toList()..sort(),
        'files': result.files,
        'tests': result.tests,
        'packages': [
          for (final pkg in result.packages)
            {'name': pkg.name, 'path': pkg.packagePath},
        ],
        'ignoredChanges': result.ignoredChanges,
      }),
    );
    return 0;
  }

  final ignored = result.ignoredChanges;
  if (ignored.isNotEmpty) {
    final shown = ignored.take(5).join(', ');
    final more = ignored.length > 5 ? ' ... (+${ignored.length - 5} more)' : '';
    stderr.writeln(
      'Note: ${ignored.length} changed non-Dart file(s) ignored: $shown$more',
    );
  }
  final what = args['print'] as String;
  final lines = switch (what) {
    'files' => result.files,
    'packages' => [for (final pkg in result.packages) pkg.name],
    _ => result.tests,
  };
  if (lines.isEmpty) stderr.writeln('No affected $what.');
  for (final line in lines) {
    stdout.writeln(line);
  }
  return 0;
}
