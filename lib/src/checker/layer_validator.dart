import 'package:glob/glob.dart';
import '../models/config_model.dart';
import '../models/scan_result.dart';

/// Violation record for Clean Architecture layer rule checking.
class LayerViolation {
  final String sourceFile;
  final String targetFile;
  final String sourceLayer;
  final String targetLayer;

  /// 1-based line of the offending directive in [sourceFile], if known.
  final int? line;

  /// Layers that [sourceLayer] is allowed to import (the rule that was broken).
  final List<String> allowedImports;

  const LayerViolation({
    required this.sourceFile,
    required this.targetFile,
    required this.sourceLayer,
    required this.targetLayer,
    this.line,
    this.allowedImports = const [],
  });

  /// The broken rule, e.g. "`presentation` may only import `domain`, `core`."
  String get rule => allowedImports.isEmpty
      ? '`$sourceLayer` may not import other layers.'
      : '`$sourceLayer` may only import '
            '${allowedImports.map((l) => '`$l`').join(', ')}.';

  /// How to resolve the violation.
  String get suggestion =>
      'Invert the dependency (e.g. an interface in `$sourceLayer` that '
      '`$targetLayer` implements), move the code to a layer `$sourceLayer` '
      'may import, or, if this dependency is intended, add `$targetLayer` to '
      'the `allowed_imports` of `$sourceLayer`.';

  Map<String, dynamic> toJson() => {
    'sourceFile': sourceFile,
    'targetFile': targetFile,
    'sourceLayer': sourceLayer,
    'targetLayer': targetLayer,
    'line': ?line,
    'allowedImports': allowedImports,
  };

  @override
  String toString() =>
      '❌ Layer Violation: [$sourceLayer] $sourceFile${line != null ? ':$line' : ''} '
      '-> [$targetLayer] $targetFile';
}

/// How well the configured layers cover the scanned files.
class LayerCoverage {
  /// Layers whose patterns matched none of the scanned files (often a typo).
  final List<String> emptyLayers;

  /// Scanned files that belong to no layer and are therefore never checked.
  final List<String> unassignedFiles;

  /// Number of scanned files assigned to each layer, in configuration order.
  final Map<String, int> layerFileCounts;

  const LayerCoverage({
    this.emptyLayers = const [],
    this.unassignedFiles = const [],
    this.layerFileCounts = const {},
  });

  Map<String, dynamic> toJson() => {
    'emptyLayers': emptyLayers,
    'unassignedFiles': unassignedFiles,
    'layerFileCounts': layerFileCounts,
  };
}

/// Validates dependency graph edges against configured Clean Architecture layers.
class LayerValidator {
  /// Validates [result] against layer definitions in [config].
  static List<LayerViolation> validate({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    if (config.layers.isEmpty) return const [];

    final resolveLayer = _layerResolver(config);
    final violations = <LayerViolation>[];

    for (final edge in result.edges) {
      final sourceLayer = resolveLayer(edge.from);
      final targetLayer = resolveLayer(edge.to);

      if (sourceLayer != null &&
          targetLayer != null &&
          sourceLayer != targetLayer) {
        final sourceDef = config.layers[sourceLayer];
        if (sourceDef != null) {
          final allowed = sourceDef.allowedImports;
          if (!allowed.contains(targetLayer)) {
            violations.add(
              LayerViolation(
                sourceFile: edge.from,
                targetFile: edge.to,
                sourceLayer: sourceLayer,
                targetLayer: targetLayer,
                line: edge.line,
                allowedImports: allowed,
              ),
            );
          }
        }
      }
    }

    return violations;
  }

  /// Reports layers that matched no files and files that matched no layer.
  static LayerCoverage coverage({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    if (config.layers.isEmpty) return const LayerCoverage();

    final resolveLayer = _layerResolver(config);
    final counts = {for (final name in config.layers.keys) name: 0};
    final unassigned = <String>[];

    for (final file in result.files.keys) {
      final layer = resolveLayer(file);
      if (layer == null) {
        unassigned.add(file);
      } else {
        counts[layer] = counts[layer]! + 1;
      }
    }

    return LayerCoverage(
      emptyLayers: [
        for (final MapEntry(:key, :value) in counts.entries)
          if (value == 0) key,
      ],
      unassignedFiles: unassigned..sort(),
      layerFileCounts: counts,
    );
  }

  /// Builds a function mapping a file path to its layer name, or `null`.
  ///
  /// In workspace/monorepo mode, paths are prefixed with the package directory
  /// (e.g. `packages/auth_pkg/lib/domain/entity.dart`). Users typically write
  /// layer patterns relative to the package root (e.g. `lib/domain/**`).
  ///
  /// To support both single-package and workspace setups transparently, we
  /// match against:
  ///   1. The full path as-is (e.g. `packages/auth_pkg/lib/domain/entity.dart`)
  ///   2. The path starting from the first `lib/` segment, effectively
  ///      stripping the workspace package prefix (e.g. `lib/domain/entity.dart`)
  static String? Function(String path) _layerResolver(ArchGuardConfig config) {
    final layerGlobs = <String, List<Glob>>{};
    config.layers.forEach((layerName, layerDef) {
      layerGlobs[layerName] = layerDef.patterns.map((p) => Glob(p)).toList();
    });

    final cache = <String, String?>{};

    return (String path) => cache.putIfAbsent(path, () {
      final normalized = path.replaceAll('\\', '/');

      // Derive the package-relative suffix: everything from `lib/` onward.
      // e.g. `packages/auth_pkg/lib/domain/entity.dart` -> `lib/domain/entity.dart`
      final libIndex = normalized.indexOf('/lib/');
      final pkgRelativePath = libIndex >= 0
          ? normalized.substring(libIndex + 1)
          : null;

      for (final entry in layerGlobs.entries) {
        final globs = entry.value;
        if (globs.any((glob) => glob.matches(normalized))) {
          return entry.key;
        }
        // Also try matching the package-relative path so patterns like
        // `lib/domain/**` work in workspace mode without any config change.
        if (pkgRelativePath != null &&
            globs.any((glob) => glob.matches(pkgRelativePath))) {
          return entry.key;
        }
      }
      return null;
    });
  }
}
