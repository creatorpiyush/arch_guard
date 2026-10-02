import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Layer definition for Clean Architecture / Layer boundary rules.
class LayerDefinition {
  final String name;
  final List<String> patterns;
  final List<String> allowedImports;

  const LayerDefinition({
    required this.name,
    required this.patterns,
    this.allowedImports = const [],
  });

  factory LayerDefinition.fromYaml(String name, Map map) {
    final patterns =
        (map['patterns'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final allowed =
        (map['allowed_imports'] as List?)?.map((e) => e.toString()).toList() ??
        [];
    return LayerDefinition(
      name: name,
      patterns: patterns,
      allowedImports: allowed,
    );
  }
}

/// Project-level configuration options loaded from `arch_guard.yaml` or `pubspec.yaml`.
///
/// The legacy `dep_graph.yaml` file and `dep_graph_visualizer:` pubspec key are
/// still read as fallbacks.
class ArchGuardConfig {
  /// Top-level keys recognised in a configuration map.
  static const knownKeys = {
    'ignore',
    'layers',
    'max_scc_size',
    'fail_on_layer_violation',
  };

  final List<String> ignorePatterns;
  final Map<String, LayerDefinition> layers;

  /// Maximum allowed number of files in a single strongly connected component.
  /// When set, any larger SCC fails the run even with `--no-fail-on-cycle`.
  final int? maxSccSize;
  final bool failOnLayerViolation;

  /// Human-readable problems found while loading the configuration
  /// (unparseable YAML, wrong value types, unknown keys, legacy names).
  final List<String> warnings;

  /// Path of the file the configuration was loaded from, if any.
  final String? sourcePath;

  const ArchGuardConfig({
    this.ignorePatterns = const [],
    this.layers = const {},
    this.maxSccSize,
    this.failOnLayerViolation = true,
    this.warnings = const [],
    this.sourcePath,
  });

  /// Loads configuration from project root directory.
  /// Priority: `arch_guard.yaml` > `dep_graph.yaml` > `pubspec.yaml (arch_guard)` > `pubspec.yaml (dep_graph_visualizer)`.
  static ArchGuardConfig load(String rootPath) {
    final absRoot = p.canonicalize(rootPath);
    final warnings = <String>[];

    Map? readYamlMap(String fileName) {
      final file = File(p.join(absRoot, fileName));
      if (!file.existsSync()) return null;
      try {
        final doc = loadYaml(file.readAsStringSync());
        if (doc is Map) return doc;
        if (doc != null) {
          warnings.add('$fileName: expected a YAML map at the top level.');
        }
      } catch (e) {
        warnings.add('$fileName: could not be parsed and was ignored ($e).');
      }
      return null;
    }

    Map? rawConfig;
    String? sourceName;

    final archGuardYaml = readYamlMap('arch_guard.yaml');
    if (archGuardYaml != null) {
      rawConfig = archGuardYaml;
      sourceName = 'arch_guard.yaml';
    }

    if (rawConfig == null) {
      final depGraphYaml = readYamlMap('dep_graph.yaml');
      if (depGraphYaml != null) {
        rawConfig = depGraphYaml;
        sourceName = 'dep_graph.yaml';
        warnings.add(
          'dep_graph.yaml is deprecated; rename it to arch_guard.yaml.',
        );
      }
    }

    if (rawConfig == null) {
      final pubspec = readYamlMap('pubspec.yaml');
      if (pubspec != null) {
        for (final key in const ['arch_guard', 'dep_graph_visualizer']) {
          if (!pubspec.containsKey(key)) continue;
          final section = pubspec[key];
          if (section is Map) {
            rawConfig = section;
            sourceName = 'pubspec.yaml ($key:)';
            if (key == 'dep_graph_visualizer') {
              warnings.add(
                'pubspec.yaml `dep_graph_visualizer:` is deprecated; '
                'rename the key to `arch_guard:`.',
              );
            }
          } else {
            warnings.add('pubspec.yaml `$key:` must be a map; ignoring it.');
          }
          break;
        }
      }
    }

    if (rawConfig == null) {
      return ArchGuardConfig(warnings: warnings);
    }

    return _parse(
      rawConfig,
      source: sourceName!,
      sourcePath: sourceName.startsWith('pubspec.yaml')
          ? p.join(absRoot, 'pubspec.yaml')
          : p.join(absRoot, sourceName),
      warnings: warnings,
    );
  }

  static ArchGuardConfig _parse(
    Map raw, {
    required String source,
    required String sourcePath,
    required List<String> warnings,
  }) {
    for (final key in raw.keys) {
      if (!knownKeys.contains(key.toString())) {
        warnings.add(
          '$source: unknown key `$key` (expected one of: ${knownKeys.join(', ')}).',
        );
      }
    }

    final ignores = <String>[];
    final rawIgnore = raw['ignore'];
    if (rawIgnore is List) {
      ignores.addAll(rawIgnore.map((e) => e.toString()));
    } else if (rawIgnore != null) {
      warnings.add('$source: `ignore` must be a list of glob patterns.');
    }

    int? maxScc;
    final rawMaxScc = raw['max_scc_size'];
    if (rawMaxScc is int && rawMaxScc > 0) {
      maxScc = rawMaxScc;
    } else if (rawMaxScc != null) {
      warnings.add('$source: `max_scc_size` must be a positive integer.');
    }

    var failOnLayer = true;
    final rawFailOnLayer = raw['fail_on_layer_violation'];
    if (rawFailOnLayer is bool) {
      failOnLayer = rawFailOnLayer;
    } else if (rawFailOnLayer != null) {
      warnings.add(
        '$source: `fail_on_layer_violation` must be true or false; using true.',
      );
    }

    final layersMap = <String, LayerDefinition>{};
    final rawLayers = raw['layers'];
    if (rawLayers is Map) {
      rawLayers.forEach((key, val) {
        final name = key.toString();
        if (val is! Map) {
          warnings.add('$source: layer `$name` must be a map; ignoring it.');
          return;
        }
        if (val['patterns'] != null && val['patterns'] is! List) {
          warnings.add('$source: layer `$name` `patterns` must be a list.');
        }
        if (val['allowed_imports'] != null && val['allowed_imports'] is! List) {
          warnings.add(
            '$source: layer `$name` `allowed_imports` must be a list.',
          );
        }
        final layer = LayerDefinition.fromYaml(name, {
          'patterns': val['patterns'] is List ? val['patterns'] : null,
          'allowed_imports': val['allowed_imports'] is List
              ? val['allowed_imports']
              : null,
        });
        if (layer.patterns.isEmpty) {
          warnings.add('$source: layer `$name` has no patterns.');
        }
        layersMap[name] = layer;
      });

      for (final layer in layersMap.values) {
        for (final allowed in layer.allowedImports) {
          if (!layersMap.containsKey(allowed)) {
            warnings.add(
              '$source: layer `${layer.name}` allows unknown layer `$allowed`.',
            );
          }
        }
      }
    } else if (rawLayers != null) {
      warnings.add('$source: `layers` must be a map of layer definitions.');
    }

    return ArchGuardConfig(
      ignorePatterns: ignores,
      layers: layersMap,
      maxSccSize: maxScc,
      failOnLayerViolation: failOnLayer,
      warnings: warnings,
      sourcePath: sourcePath,
    );
  }
}

/// Former name of [ArchGuardConfig], kept for backwards compatibility.
@Deprecated('Use ArchGuardConfig instead.')
typedef DepGraphConfig = ArchGuardConfig;

typedef DynamicMap = Map<dynamic, dynamic>;
