import 'dart:io';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/file_node.dart';
import '../models/scan_result.dart';
import '../models/workspace_package.dart';
import 'default_excludes.dart';
import 'ignore_comments.dart';
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

  /// Folders scanned inside each workspace member, relative to the member
  /// (`lib`, `test`). Missing folders are skipped.
  final List<String> memberScanDirs;

  /// Creates a scanner for the project at [rootPath].
  ProjectScanner({
    required this.rootPath,
    this.scanDirs = const ['lib'],
    this.exclude = const [],
    this.enableWorkspace = true,
    this.memberScanDirs = const ['lib'],
  });

  /// Performs the scan and returns a [ScanResult].
  Future<ScanResult> scan() async {
    final absRoot = p.canonicalize(rootPath);
    final primaryPkgName =
        PubspecReader.readPackageName(absRoot) ?? p.basename(absRoot);

    final excludeMatchers = [
      ...defaultExcludePatterns,
      ...exclude,
    ].map(excludeMatcher).toList();

    bool isExcluded(String relPath) {
      final normalized = relPath.replaceAll('\\', '/');
      return excludeMatchers.any((matches) => matches(normalized));
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
    final packageImports = <PackageImport>[];

    // Determine target directories to scan. Member packages contribute their
    // [memberScanDirs]; the root package (or a plain project) honours [scanDirs].
    final targetScanDirs = <String>[];
    if (workspacePkgs.isNotEmpty) {
      // A workspace root without lib/ is not a member, but its other scan
      // dirs (test/) still belong to the scan.
      if (!workspacePkgs.values.any((pkg) => pkg.packagePath == '.')) {
        targetScanDirs.addAll(scanDirs);
      }
      for (final pkg in workspacePkgs.values) {
        if (pkg.packagePath == '.') {
          targetScanDirs.addAll(scanDirs);
        } else {
          for (final dir in memberScanDirs) {
            targetScanDirs.add('${pkg.packagePath}/$dir');
          }
        }
      }
    } else {
      targetScanDirs.addAll(scanDirs);
    }

    for (final scanDir in targetScanDirs) {
      final dirPath = p.join(absRoot, scanDir);
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      // Identify owning package name for this directory. The longest
      // matching member path wins, so nested members own their own files.
      String currentPkgName = primaryPkgName;
      var ownerPathLength = -1;
      for (final entry in workspacePkgs.entries) {
        final pkg = entry.value;
        if ((scanDir == pkg.libPath ||
                scanDir.startsWith('${pkg.packagePath}/')) &&
            pkg.packagePath.length > ownerPathLength) {
          currentPkgName = entry.key;
          ownerPathLength = pkg.packagePath.length;
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
              _readFile(
                relPath: relPath,
                absolutePath: entity.path,
                content: await entity.readAsString(),
                packageName: currentPkgName,
                workspaceLibs: workspaceLibMap.isNotEmpty
                    ? workspaceLibMap
                    : null,
                files: filesMap,
                edges: rawEdges,
                packageImports: packageImports,
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

    return _finish(
      packageName: primaryPkgName,
      files: filesMap,
      rawEdges: rawEdges,
      packageImports: packageImports,
      workspacePackageCount: workspacePkgs.isNotEmpty
          ? workspacePkgs.length
          : 1,
      skippedFiles: skippedFiles,
      packages: workspacePkgs.values.toList()
        ..sort((x, y) => x.packagePath.compareTo(y.packagePath)),
    );
  }

  /// Builds a [ScanResult] from file contents instead of the file system:
  /// [sources] maps project-relative `/` paths (e.g. `lib/a.dart`) to their
  /// contents. A single package: no workspace discovery and no excludes.
  static ScanResult scanSources({
    required String packageName,
    required Map<String, String> sources,
  }) {
    final files = <String, FileNode>{};
    final rawEdges = <_TempEdge>[];
    final packageImports = <PackageImport>[];
    for (final path in sources.keys.toList()..sort()) {
      _readFile(
        relPath: path,
        absolutePath: path,
        content: sources[path]!,
        packageName: packageName,
        workspaceLibs: null,
        files: files,
        edges: rawEdges,
        packageImports: packageImports,
      );
    }
    return _finish(
      packageName: packageName,
      files: files,
      rawEdges: rawEdges,
      packageImports: packageImports,
    );
  }

  /// Returns a test for whether a `/` path matches the glob [pattern].
  ///
  /// The common shapes `**/*.ext` and `**/name/**` (all default excludes)
  /// are checked with string operations; `Glob.matches` is slow enough to
  /// show up when run on tens of thousands of files.
  static bool Function(String) excludeMatcher(String pattern) {
    const special = r'*?[]{}\\';
    bool plain(String s) => s.isNotEmpty && !s.split('').any(special.contains);
    if (pattern.startsWith('**/*.') && plain(pattern.substring(5))) {
      final suffix = pattern.substring(4);
      return (path) => path.endsWith(suffix);
    }
    if (pattern.startsWith('**/') && pattern.endsWith('/**')) {
      final name = pattern.substring(3, pattern.length - 3);
      if (plain(name) && !name.contains('/')) {
        final segment = '/$name/';
        return (path) => '/$path'.contains(segment);
      }
    }
    return Glob(pattern).matches;
  }

  /// Reads one file's directives into [files], [edges] and [packageImports].
  static void _readFile({
    required String relPath,
    required String absolutePath,
    required String content,
    required String packageName,
    required Map<String, String>? workspaceLibs,
    required Map<String, FileNode> files,
    required List<_TempEdge> edges,
    required List<PackageImport> packageImports,
  }) {
    final directives = ImportReader.extractDirectives(content);
    final ignores = IgnoreComments.parse(content);
    final imports = <String>[];
    final exports = <String>[];
    final parts = <String>[];
    for (final directive in directives) {
      // The plugin reports at the URI, so an ignore above the URI's line
      // counts as well as one above the directive keyword.
      final ignored = {
        ...ignores.codesAt(directive.line),
        ...ignores.codesAt(directive.uriLine),
      };
      switch (directive.type) {
        case 'export':
          exports.add(directive.uri);
        case 'part':
          parts.add(directive.uri);
        default:
          imports.add(directive.uri);
      }

      final package = directive.type == 'part'
          ? null
          : PackageImport.packageOf(directive.uri);
      if (package != null && package != packageName) {
        packageImports.add(
          PackageImport(
            file: relPath,
            uri: directive.uri,
            package: package,
            type: directive.type,
            line: directive.line,
            ignored: ignored,
          ),
        );
      }

      final resolvedTarget = ImportReader.resolveUri(
        uri: directive.uri,
        packageName: packageName,
        importingFileRelativePath: relPath,
        workspacePackages: workspaceLibs,
      );
      if (resolvedTarget != null) {
        edges.add(
          _TempEdge(
            from: relPath,
            to: resolvedTarget,
            type: directive.type,
            line: directive.line,
            condition: directive.condition,
            ignored: ignored,
          ),
        );
      }
    }
    files[relPath] = FileNode(
      relativePath: relPath,
      absolutePath: absolutePath,
      imports: imports,
      exports: exports,
      parts: parts,
    );
  }

  /// Drops edges to unscanned files and sorts everything for stable output.
  static ScanResult _finish({
    required String packageName,
    required Map<String, FileNode> files,
    required List<_TempEdge> rawEdges,
    required List<PackageImport> packageImports,
    int workspacePackageCount = 1,
    Map<String, String> skippedFiles = const {},
    List<WorkspacePackage> packages = const [],
  }) {
    // Keep only edges whose target was actually scanned, so files outside the
    // scan scope (or non-existent paths) never become phantom graph nodes.
    final validEdges = <GraphEdge>[];
    for (final edge in rawEdges) {
      if (files.containsKey(edge.to)) {
        validEdges.add(
          GraphEdge(
            from: edge.from,
            to: edge.to,
            type: edge.type,
            line: edge.line,
            condition: edge.condition,
            ignored: edge.ignored,
          ),
        );
      }
    }

    // Files are read in parallel, so sort for a stable order.
    packageImports.sort(
      (a, b) => a.file != b.file
          ? a.file.compareTo(b.file)
          : (a.line ?? 0).compareTo(b.line ?? 0),
    );

    // Sorted so graph traversal, cycle numbering and reports are identical
    // between runs (files are read in parallel and finish in any order).
    final sortedFiles = Map.fromEntries(
      files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    validEdges.sort((a, b) {
      var c = a.from.compareTo(b.from);
      if (c != 0) return c;
      c = a.to.compareTo(b.to);
      if (c != 0) return c;
      c = a.type.compareTo(b.type);
      if (c != 0) return c;
      return (a.line ?? 0).compareTo(b.line ?? 0);
    });

    return ScanResult(
      packageName: packageName,
      files: sortedFiles,
      edges: validEdges,
      workspacePackageCount: workspacePackageCount,
      skippedFiles: {
        for (final f in skippedFiles.keys.toList()..sort()) f: skippedFiles[f]!,
      },
      packageImports: packageImports,
      packages: packages,
    );
  }
}

class _TempEdge {
  final String from;
  final String to;
  final String type;
  final int? line;
  final String? condition;
  final Set<String> ignored;

  _TempEdge({
    required this.from,
    required this.to,
    required this.type,
    this.line,
    this.condition,
    this.ignored = const {},
  });
}
