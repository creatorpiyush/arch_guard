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
    (changed, result) = await findAffected(
      absProjectPath,
      since,
      exclude: args['exclude'] as List<String>,
      enableWorkspace: args['workspace'] as bool,
    );
  } on GitException catch (e) {
    stderr.writeln('Error: ${e.message}');
    return 2;
  } on FileSystemException catch (e) {
    stderr.writeln('Error: ${e.message}: ${e.path}');
    return 2;
  }

  if (args['json'] as bool) {
    stdout.writeln(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(affectedJson(since, changed, result)),
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

/// The files changed since [since] and what they can affect, scanning
/// `lib/`, `test/` and `integration_test/` of [absProjectPath]. Throws
/// [GitException] when git fails.
Future<(Set<String>, AffectedResult)> findAffected(
  String absProjectPath,
  String since, {
  List<String> exclude = const [],
  bool enableWorkspace = true,
}) async {
  final changed = GitChanges.since(since, projectRoot: absProjectPath);
  final scan = await ProjectScanner(
    rootPath: absProjectPath,
    scanDirs: _scanDirs,
    memberScanDirs: _scanDirs,
    exclude: exclude,
    enableWorkspace: enableWorkspace,
  ).scan();
  return (changed, AffectedFiles.find(result: scan, changed: changed));
}

/// The `arch_guard affected --json` report.
Map<String, Object?> affectedJson(
  String since,
  Set<String> changed,
  AffectedResult result,
) => {
  'since': since,
  'changedFiles': changed.toList()..sort(),
  'files': result.files,
  'tests': result.tests,
  'packages': [
    for (final pkg in result.packages)
      {'name': pkg.name, 'path': pkg.packagePath},
  ],
  'ignoredChanges': result.ignoredChanges,
};
