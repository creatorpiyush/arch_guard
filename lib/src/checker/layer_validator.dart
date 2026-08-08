import 'package:glob/glob.dart';
import '../models/config_model.dart';
import '../models/scan_result.dart';

/// Violation record for Clean Architecture layer rule checking.
class LayerViolation {
  final String sourceFile;
  final String targetFile;
  final String sourceLayer;
  final String targetLayer;

  const LayerViolation({
    required this.sourceFile,
    required this.targetFile,
    required this.sourceLayer,
    required this.targetLayer,
  });

  Map<String, dynamic> toJson() => {
    'sourceFile': sourceFile,
    'targetFile': targetFile,
    'sourceLayer': sourceLayer,
    'targetLayer': targetLayer,
  };

  @override
  String toString() =>
      '❌ Layer Violation: [$sourceLayer] $sourceFile -> [$targetLayer] $targetFile';
}

/// Validates dependency graph edges against configured Clean Architecture layers.
class LayerValidator {
  /// Validates [result] against layer definitions in [config].
  static List<LayerViolation> validate({
    required ScanResult result,
    required DepGraphConfig config,
  }) {
    if (config.layers.isEmpty) return const [];

    final violations = <LayerViolation>[];
    final layerGlobs = <String, List<Glob>>{};

    // Compile globs per layer
    config.layers.forEach((layerName, layerDef) {
      layerGlobs[layerName] = layerDef.patterns.map((p) => Glob(p)).toList();
    });

    // Helper to determine layer of a file path.
    //
    // In workspace/monorepo mode, paths are prefixed with the package directory
    // (e.g. `packages/auth_pkg/lib/domain/entity.dart`). Users typically write
    // layer patterns relative to the package root (e.g. `lib/domain/**`).
    //
    // To support both single-package and workspace setups transparently, we
    // match against:
    //   1. The full path as-is (e.g. `packages/auth_pkg/lib/domain/entity.dart`)
    //   2. The path starting from the first `lib/` segment, effectively
    //      stripping the workspace package prefix (e.g. `lib/domain/entity.dart`)
    String? resolveLayer(String path) {
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
    }

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
              ),
            );
          }
        }
      }
    }

    return violations;
  }
}
