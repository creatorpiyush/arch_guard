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

    // Helper to determine layer of a file path
    String? resolveLayer(String path) {
      final normalized = path.replaceAll('\\', '/');
      for (final entry in layerGlobs.entries) {
        if (entry.value.any((glob) => glob.matches(normalized))) {
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
