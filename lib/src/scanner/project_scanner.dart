import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/file_node.dart';
import '../models/scan_result.dart';
import '../models/workspace_package.dart';
import 'default_excludes.dart';
import 'import_reader.dart';
import 'pubspec_reader.dart';

/// Scans a Dart/Flutter project or monorepo workspace directory to discover files and dependency edges.
class ProjectScanner {
  /// The root directory of the project or workspace.
  final String rootPath;

  /// Subdirectories within project root to scan (used when scanning a single package).
  final List<String> scanDirs;

  /// Custom glob patterns to exclude in addition to default excludes.
  final List<String> exclude;

  /// Whether to auto-discover and scan member packages in a Dart 3.6+ workspace or monorepo.
  final bool enableWorkspace;

  ProjectScanner({
    required this.rootPath,
    this.scanDirs = const ['lib'],
    this.exclude = const [],
    this.enableWorkspace = true,
  });

  /// Performs the scan and returns a [ScanResult].
  Future<ScanResult> scan() async {
    final absRoot = p.canonicalize(rootPath);
    final primaryPkgName =
        PubspecReader.readPackageName(absRoot) ?? p.basename(absRoot);

    final excludeGlobs = [
      ...defaultExcludePatterns,
      ...exclude,
    ].map((pattern) => Glob(pattern)).toList();

    bool isExcluded(String relPath) {
      final normalized = relPath.replaceAll('\\', '/');
      return excludeGlobs.any((glob) => glob.matches(normalized));
    }

    // Discover workspace packages if enabled
    final workspacePkgs = enableWorkspace
        ? PubspecReader.discoverWorkspacePackages(absRoot)
        : <String, WorkspacePackage>{};

    final workspaceLibMap = <String, String>{};
    workspacePkgs.forEach((name, pkg) {
      workspaceLibMap[name] = pkg.libPath;
    });

    final filesMap = <String, FileNode>{};
    final skippedFiles = <String, String>{};
    final rawEdges = <_TempEdge>[];

    // Determine target directories to scan. Member packages contribute their
    // lib directories; the root package (or a plain project) honours [scanDirs].
    final targetScanDirs = <String>[];
    if (workspacePkgs.isNotEmpty) {
      for (final pkg in workspacePkgs.values) {
        if (pkg.packagePath == '.') {
          targetScanDirs.addAll(scanDirs);
        } else {
          targetScanDirs.add(pkg.libPath);
        }
      }
    } else {
      targetScanDirs.addAll(scanDirs);
    }

    for (final scanDir in targetScanDirs) {
      final dirPath = p.join(absRoot, scanDir);
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      // Identify owning package name for this directory
      String currentPkgName = primaryPkgName;
      if (workspacePkgs.isNotEmpty) {
        for (final entry in workspacePkgs.entries) {
          if (scanDir == entry.value.libPath ||
              scanDir.startsWith('${entry.value.packagePath}/')) {
            currentPkgName = entry.key;
            break;
          }
        }
      }

      final dartFiles =
          <File, String>{}; // File entity to relative path mapping
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final relPath = p
            .relative(entity.path, from: absRoot)
            .replaceAll('\\', '/');
        if (!isExcluded(relPath)) {
          dartFiles[entity] = relPath;
        }
      }

      // Process Dart files in parallel batches of 64
      final fileEntries = dartFiles.entries.toList();
      const chunkSize = 64;
      for (var i = 0; i < fileEntries.length; i += chunkSize) {
        final chunk = fileEntries.sublist(
          i,
          i + chunkSize > fileEntries.length
              ? fileEntries.length
              : i + chunkSize,
        );

        await Future.wait(
          chunk.map((entry) async {
            final entity = entry.key;
            final relPath = entry.value;
            try {
              final content = await entity.readAsString();
              final directives = ImportReader.extractDirectives(content);

              final imports = <String>[];
              final exports = <String>[];
              final parts = <String>[];
              final localRawEdges = <_TempEdge>[];

              for (final directive in directives) {
                switch (directive.type) {
                  case 'export':
                    exports.add(directive.uri);
                  case 'part':
                    parts.add(directive.uri);
                  default:
                    imports.add(directive.uri);
                }

                final resolvedTarget = ImportReader.resolveUri(
                  uri: directive.uri,
                  packageName: currentPkgName,
                  importingFileRelativePath: relPath,
                  workspacePackages: workspaceLibMap.isNotEmpty
                      ? workspaceLibMap
                      : null,
                );

                if (resolvedTarget != null) {
                  localRawEdges.add(
                    _TempEdge(
                      from: relPath,
                      to: resolvedTarget,
                      type: directive.type,
                    ),
                  );
                }
              }

              rawEdges.addAll(localRawEdges);
              filesMap[relPath] = FileNode(
                relativePath: relPath,
                absolutePath: entity.path,
                imports: imports,
                exports: exports,
                parts: parts,
              );
            } on FileSystemException catch (e) {
              skippedFiles[relPath] = e.osError?.message ?? e.message;
            } catch (e) {
              skippedFiles[relPath] = e.toString();
            }
          }),
        );
      }
    }

    // Keep only edges whose target was actually scanned, so files outside the
    // scan scope (or non-existent paths) never become phantom graph nodes.
    final validEdges = <GraphEdge>[];
    for (final edge in rawEdges) {
      if (filesMap.containsKey(edge.to)) {
        validEdges.add(
          GraphEdge(from: edge.from, to: edge.to, type: edge.type),
        );
      }
    }

    final pkgCount = workspacePkgs.isNotEmpty ? workspacePkgs.length : 1;

    return ScanResult(
      packageName: primaryPkgName,
      files: filesMap,
      edges: validEdges,
      workspacePackageCount: pkgCount,
      skippedFiles: skippedFiles,
    );
  }
}

class _TempEdge {
  final String from;
  final String to;
  final String type;

  _TempEdge({required this.from, required this.to, required this.type});
}
