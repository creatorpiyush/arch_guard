import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/workspace_package.dart';

/// Reads pubspec.yaml files to extract package and workspace information.
class PubspecReader {
  /// Reads the package name from `pubspec.yaml` in [projectRoot].
  /// Returns `null` if `pubspec.yaml` does not exist or is invalid.
  static String? readPackageName(String projectRoot) {
    final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return null;
    }

    try {
      final content = pubspecFile.readAsStringSync();
      final yamlMap = loadYaml(content);
      if (yamlMap is Map && yamlMap.containsKey('name')) {
        return yamlMap['name']?.toString();
      }
    } catch (_) {
      // Fallback if parsing fails
    }
    return null;
  }

  /// Default member locations for monorepos without an explicit `workspace:` list
  /// (Melos-style `packages/*` and `apps/*` layouts).
  static const List<String> defaultMemberPatterns = ['packages/**', 'apps/**'];

  /// Discovers all member packages in a Dart 3.6+ workspace or monorepo under [projectRoot].
  ///
  /// Members are taken from the root `pubspec.yaml` `workspace:` list when present,
  /// otherwise from [defaultMemberPatterns]. Returns an empty map when no member
  /// packages are found, so a plain single-package project is never treated as a
  /// workspace. When members exist, the root package (if it has a `lib/`) is
  /// included under package path `.`.
  ///
  /// Maps package name -> [WorkspacePackage].
  static Map<String, WorkspacePackage> discoverWorkspacePackages(
    String projectRoot,
  ) {
    final absRoot = p.canonicalize(projectRoot);
    final results = <String, WorkspacePackage>{};

    final rootPubspecFile = File(p.join(absRoot, 'pubspec.yaml'));
    final workspaceGlobs = <Glob>[];
    WorkspacePackage? rootPackage;

    if (rootPubspecFile.existsSync()) {
      try {
        final content = rootPubspecFile.readAsStringSync();
        final yamlMap = loadYaml(content);
        if (yamlMap is Map) {
          final rootName = yamlMap['name']?.toString();
          if (rootName != null &&
              Directory(p.join(absRoot, 'lib')).existsSync()) {
            rootPackage = WorkspacePackage(
              name: rootName,
              packagePath: '.',
              libPath: 'lib',
            );
          }

          final workspaceEntries = yamlMap['workspace'];
          if (workspaceEntries is List) {
            for (final entry in workspaceEntries) {
              workspaceGlobs.add(Glob(entry.toString().replaceAll('\\', '/')));
            }
          }
        }
      } catch (_) {}
    }

    final rootDir = Directory(absRoot);
    if (!rootDir.existsSync()) return results;

    // Without an explicit workspace list, only auto-discover conventional
    // monorepo locations, and skip example/test packages nested inside them.
    final isExplicitWorkspace = workspaceGlobs.isNotEmpty;
    final memberGlobs = isExplicitWorkspace
        ? workspaceGlobs
        : defaultMemberPatterns.map((pattern) => Glob(pattern)).toList();

    final ignoredDirs = {
      '.dart_tool',
      'build',
      '.git',
      '.idea',
      '.fvm',
      'node_modules',
      'arch_guard_output',
      'dep_graph_output',
      '.github',
      if (!isExplicitWorkspace) ...{'example', 'test', 'tool'},
    };

    void scanDirectory(Directory dir, int currentDepth) {
      if (currentDepth > 4) return;

      try {
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is! Directory) continue;

          final dirName = p.basename(entity.path);
          if (ignoredDirs.contains(dirName)) continue;

          final relPath = p
              .relative(entity.path, from: absRoot)
              .replaceAll('\\', '/');

          // Check if this directory contains a pubspec.yaml
          final pubspecFile = File(p.join(entity.path, 'pubspec.yaml'));
          final libDir = Directory(p.join(entity.path, 'lib'));

          if (pubspecFile.existsSync() && libDir.existsSync()) {
            if (memberGlobs.any((g) => g.matches(relPath))) {
              final pkgName = readPackageName(entity.path);
              if (pkgName != null && pkgName.isNotEmpty) {
                final relLibPath = p
                    .relative(libDir.path, from: absRoot)
                    .replaceAll('\\', '/');
                results[pkgName] = WorkspacePackage(
                  name: pkgName,
                  packagePath: relPath,
                  libPath: relLibPath,
                );
              }
            }
          }

          // Recursively search subdirectories
          scanDirectory(entity, currentDepth + 1);
        }
      } catch (_) {}
    }

    scanDirectory(rootDir, 1);

    if (results.isEmpty) return results;
    final root = rootPackage;
    if (root != null && !results.containsKey(root.name)) {
      results[root.name] = root;
    }
    return results;
  }
}
