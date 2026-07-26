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

  /// Discovers all member packages in a Dart 3.6+ workspace or monorepo under [projectRoot].
  ///
  /// Maps package name -> [WorkspacePackage].
  static Map<String, WorkspacePackage> discoverWorkspacePackages(
    String projectRoot,
  ) {
    final absRoot = p.canonicalize(projectRoot);
    final results = <String, WorkspacePackage>{};

    final rootPubspecFile = File(p.join(absRoot, 'pubspec.yaml'));
    final workspaceGlobs = <Glob>[];

    if (rootPubspecFile.existsSync()) {
      try {
        final content = rootPubspecFile.readAsStringSync();
        final yamlMap = loadYaml(content);
        if (yamlMap is Map) {
          final rootName = yamlMap['name']?.toString();
          if (rootName != null &&
              Directory(p.join(absRoot, 'lib')).existsSync()) {
            results[rootName] = WorkspacePackage(
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

    // Default search locations if no explicit workspace list is given or for general monorepos
    final rootDir = Directory(absRoot);
    if (!rootDir.existsSync()) return results;

    final ignoredDirs = {
      '.dart_tool',
      'build',
      '.git',
      '.idea',
      'node_modules',
      'dep_graph_output',
      '.github',
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
            // Check if matches workspace globs (if any defined), or auto-discovered monorepo pkg
            final matchesWorkspace =
                workspaceGlobs.isEmpty ||
                workspaceGlobs.any((g) => g.matches(relPath));

            if (matchesWorkspace) {
              final pkgName = readPackageName(entity.path);
              if (pkgName != null && pkgName.isNotEmpty) {
                final relLibPath = p.relative(libDir.path, from: absRoot);
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

    return results;
  }
}
