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

/// Project-level configuration options loaded from `dep_graph.yaml` or `pubspec.yaml`.
class DepGraphConfig {
  final List<String> ignorePatterns;
  final Map<String, LayerDefinition> layers;
  final int? maxSccSize;
  final bool failOnLayerViolation;

  const DepGraphConfig({
    this.ignorePatterns = const [],
    this.layers = const {},
    this.maxSccSize,
    this.failOnLayerViolation = true,
  });

  /// Loads configuration from project root directory.
  /// Priority: `dep_graph.yaml` overrides `pubspec.yaml`.
  static DepGraphConfig load(String rootPath) {
    final absRoot = p.canonicalize(rootPath);
    final depGraphYamlPath = p.join(absRoot, 'dep_graph.yaml');
    final pubspecYamlPath = p.join(absRoot, 'pubspec.yaml');

    DynamicMap? rawConfig;

    if (File(depGraphYamlPath).existsSync()) {
      try {
        final content = File(depGraphYamlPath).readAsStringSync();
        final doc = loadYaml(content);
        if (doc is Map) rawConfig = doc;
      } catch (_) {}
    }

    if (rawConfig == null && File(pubspecYamlPath).existsSync()) {
      try {
        final content = File(pubspecYamlPath).readAsStringSync();
        final doc = loadYaml(content);
        if (doc is Map && doc.containsKey('dep_graph_visualizer')) {
          rawConfig = doc['dep_graph_visualizer'];
        }
      } catch (_) {}
    }

    if (rawConfig == null) {
      return const DepGraphConfig();
    }

    final ignores =
        (rawConfig['ignore'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final maxScc = rawConfig['max_scc_size'] is int
        ? rawConfig['max_scc_size'] as int
        : null;
    final failOnLayer = rawConfig['fail_on_layer_violation'] as bool? ?? true;

    final layersMap = <String, LayerDefinition>{};
    if (rawConfig['layers'] is Map) {
      (rawConfig['layers'] as Map).forEach((key, val) {
        if (val is Map) {
          layersMap[key.toString()] = LayerDefinition.fromYaml(
            key.toString(),
            val,
          );
        }
      });
    }

    return DepGraphConfig(
      ignorePatterns: ignores,
      layers: layersMap,
      maxSccSize: maxScc,
      failOnLayerViolation: failOnLayer,
    );
  }
}

typedef DynamicMap = Map<dynamic, dynamic>;
