import 'package:glob/glob.dart';
import '../models/config_model.dart';
import '../models/scan_result.dart';

/// Violation record for Clean Architecture layer rule checking.
class LayerViolation {
  /// Path of the importing file.
  final String sourceFile;

  /// Path of the imported file.
  final String targetFile;

  /// Layer that [sourceFile] belongs to.
  final String sourceLayer;

  /// Layer that [targetFile] belongs to.
  final String targetLayer;

  /// 1-based line of the offending directive in [sourceFile], if known.
  final int? line;

  /// Layers that [sourceLayer] is allowed to import (the rule that was broken).
  final List<String> allowedImports;

  /// Files in no layer that re-export [targetFile] to [sourceFile], in order
  /// (for example a barrel `lib/exports.dart`). Empty for a direct import.
  final List<String> via;

  /// Creates a violation of [sourceLayer] importing [targetLayer].
  const LayerViolation({
    required this.sourceFile,
    required this.targetFile,
    required this.sourceLayer,
    required this.targetLayer,
    this.line,
    this.allowedImports = const [],
    this.via = const [],
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

  /// JSON form used by the JSON exporter and the baseline.
  Map<String, dynamic> toJson() => {
    'sourceFile': sourceFile,
    'targetFile': targetFile,
    'sourceLayer': sourceLayer,
    'targetLayer': targetLayer,
    'line': ?line,
    'allowedImports': allowedImports,
    if (via.isNotEmpty) 'via': via,
  };

  /// ` (via lib/exports.dart)` for a re-exported import, otherwise empty.
  String get viaSuffix => via.isEmpty ? '' : ' (via ${via.join(' -> ')})';

  @override
  String toString() =>
      '❌ Layer Violation: [$sourceLayer] $sourceFile${line != null ? ':$line' : ''} '
      '-> [$targetLayer] $targetFile$viaSuffix';
}

/// How well the configured layers cover the scanned files.
class LayerCoverage {
  /// Layers whose patterns matched none of the scanned files (often a typo).
  final List<String> emptyLayers;

  /// Scanned files that belong to no layer and are therefore never checked.
  final List<String> unassignedFiles;

  /// Number of scanned files assigned to each layer, in configuration order.
  final Map<String, int> layerFileCounts;

  /// Creates a coverage report.
  const LayerCoverage({
    this.emptyLayers = const [],
    this.unassignedFiles = const [],
    this.layerFileCounts = const {},
  });

  /// JSON form used by the JSON exporter.
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
    final check = checker(config);
    final violations = [
      for (final edge in result.edges)
        ?check(edge.from, edge.to, line: edge.line),
    ];

    // A file in no layer is never checked, so a barrel there would hide
    // `a -> barrel -> c` from the rules. Follow its re-exports to the first
    // files that have a layer; their own exports are checked as edges above.
    final resolveLayer = layerResolver(config);
    final exports = <String, List<String>>{};
    for (final edge in result.edges) {
      if (edge.type == 'export') {
        exports.putIfAbsent(edge.from, () => []).add(edge.to);
      }
    }
    final reported = {
      for (final v in violations) '${v.sourceFile}\n${v.targetFile}',
    };
    for (final edge in result.edges) {
      if (resolveLayer(edge.from) == null || resolveLayer(edge.to) != null) {
        continue;
      }
      final seen = {edge.to};
      void follow(String barrel, List<String> via) {
        for (final next in exports[barrel] ?? const <String>[]) {
          if (!seen.add(next)) continue;
          if (resolveLayer(next) == null) {
            follow(next, [...via, next]);
            continue;
          }
          final v = check(edge.from, next, line: edge.line, via: via);
          if (v != null && reported.add('${edge.from}\n$next')) {
            violations.add(v);
          }
        }
      }

      follow(edge.to, [edge.to]);
    }
    return violations;
  }

  /// Returns a function that checks one import of [to] by [from], reached
  /// through the re-exporting files [via] (empty for a direct import).
  static LayerViolation? Function(
    String from,
    String to, {
    int? line,
    List<String> via,
  })
  checker(ArchGuardConfig config) {
    final resolveLayer = layerResolver(config);
    return (from, to, {line, via = const []}) {
      final sourceLayer = resolveLayer(from);
      final targetLayer = resolveLayer(to);
      if (sourceLayer == null ||
          targetLayer == null ||
          sourceLayer == targetLayer) {
        return null;
      }
      final allowed = config.layers[sourceLayer]?.allowedImports;
      if (allowed == null || allowed.contains(targetLayer)) return null;
      return LayerViolation(
        sourceFile: from,
        targetFile: to,
        sourceLayer: sourceLayer,
        targetLayer: targetLayer,
        line: line,
        allowedImports: allowed,
        via: via,
      );
    };
  }

  /// Reports layers that matched no files and files that matched no layer.
  static LayerCoverage coverage({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    if (config.layers.isEmpty) return const LayerCoverage();

    final resolveLayer = layerResolver(config);
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

  /// Returns a function mapping a file path to its layer name, or `null`.
  /// Results are cached, so build one resolver per config and reuse it.
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
  static String? Function(String path) layerResolver(ArchGuardConfig config) {
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
