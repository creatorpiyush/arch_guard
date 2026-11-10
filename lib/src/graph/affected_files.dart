import 'package:path/path.dart' as p;

import '../models/scan_result.dart';
import '../models/workspace_package.dart';
import '../scanner/import_reader.dart';

/// What a set of changed files can affect, from [AffectedFiles.find].
class AffectedResult {
  /// Changed and dependent files, sorted.
  final List<String> files;

  /// The [files] whose name ends in `_test.dart`, sorted.
  final List<String> tests;

  /// Packages that own at least one of [files], sorted by name. A single
  /// package project reports its root as path `.`.
  final List<WorkspacePackage> packages;

  /// Changed files that affect no Dart file (assets, docs), sorted.
  final List<String> ignoredChanges;

  /// Creates a result.
  const AffectedResult({
    required this.files,
    required this.tests,
    required this.packages,
    required this.ignoredChanges,
  });
}

/// Finds the files, tests and packages that changed files can affect.
class AffectedFiles {
  /// Walks [result]'s edges backwards from [changed] (project-relative `/`
  /// paths, as `GitChanges.since` returns them). Every edge counts,
  /// including ignored and conditional ones.
  ///
  /// A changed Dart file that was not scanned (deleted, generated, excluded)
  /// affects the files whose directives point at it. A changed
  /// `pubspec.yaml` or `pubspec.lock` affects its whole package; at the
  /// root it affects every file, since a workspace shares one lock file.
  static AffectedResult find({
    required ScanResult result,
    required Set<String> changed,
  }) {
    final root = result.packages.firstWhere(
      (pkg) => pkg.packagePath == '.',
      orElse: () => WorkspacePackage(
        name: result.packageName,
        packagePath: '.',
        libPath: 'lib',
      ),
    );
    final members = result.packages.where((pkg) => pkg.packagePath != '.');
    WorkspacePackage ownerOf(String path) {
      WorkspacePackage owner = root;
      for (final pkg in members) {
        if (path.startsWith('${pkg.packagePath}/') &&
            (owner == root ||
                pkg.packagePath.length > owner.packagePath.length)) {
          owner = pkg;
        }
      }
      return owner;
    }

    final seeds = <String>{};
    final ignored = <String>[];
    final unscanned = <String>{};
    for (final path in changed) {
      final name = p.posix.basename(path);
      if (result.files.containsKey(path)) {
        seeds.add(path);
      } else if (path.endsWith('.dart')) {
        unscanned.add(path);
      } else if (name == 'pubspec.yaml' || name == 'pubspec.lock') {
        final dir = p.posix.dirname(path);
        final pkg = dir == '.'
            ? null
            : members.where((m) => m.packagePath == dir).firstOrNull;
        if (dir != '.' && pkg == null) {
          ignored.add(path);
          continue;
        }
        for (final file in result.files.keys) {
          if (pkg == null || ownerOf(file) == pkg) seeds.add(file);
        }
      } else {
        ignored.add(path);
      }
    }

    if (unscanned.isNotEmpty) {
      final libs = result.packages.isEmpty
          ? null
          : {for (final pkg in result.packages) pkg.name: pkg.libPath};
      for (final node in result.files.values) {
        final from = node.relativePath;
        final pkgName = ownerOf(from).name;
        for (final uri in [...node.imports, ...node.exports, ...node.parts]) {
          final target = ImportReader.resolveUri(
            uri: uri,
            packageName: pkgName,
            importingFileRelativePath: from,
            workspacePackages: libs,
          );
          if (unscanned.contains(target)) seeds.add(from);
        }
      }
    }

    final dependents = <String, List<String>>{};
    for (final edge in result.edges) {
      (dependents[edge.to] ??= []).add(edge.from);
    }
    final affected = {...seeds};
    final queue = [...seeds];
    while (queue.isNotEmpty) {
      for (final from in dependents[queue.removeLast()] ?? const <String>[]) {
        if (affected.add(from)) queue.add(from);
      }
    }

    final files = affected.toList()..sort();
    final packages = {for (final f in files) ownerOf(f)}.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return AffectedResult(
      files: files,
      tests: [
        for (final f in files)
          if (f.endsWith('_test.dart')) f,
      ],
      packages: packages,
      ignoredChanges: ignored..sort(),
    );
  }
}
