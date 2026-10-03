import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'layer_definition.dart';
import 'layer_presets.dart';

export 'layer_definition.dart';

/// Project-level configuration options loaded from `arch_guard.yaml` or `pubspec.yaml`.
///
/// The legacy `dep_graph.yaml` file and `dep_graph_visualizer:` pubspec key are
/// still read as fallbacks.
class ArchGuardConfig {
  /// Top-level keys recognised in a configuration map.
  static const knownKeys = {
    'ignore',
    'preset',
    'layers',
    'max_scc_size',
    'fail_on_layer_violation',
  };

  /// Glob patterns of files left out of the scan.
  final List<String> ignorePatterns;

  /// Layers in effect: the [preset]'s layers, overridden or extended by the
  /// `layers:` section.
  final Map<String, LayerDefinition> layers;

  /// Name of the layer preset in use (see [LayerPresets]), if any.
  final String? preset;

  /// Layers that come from [preset] and are not mentioned under `layers:`.
  /// Presets cover layouts a project may only partly use, so these layers
  /// matching no files is expected rather than a configuration mistake.
  final Set<String> presetOnlyLayers;

  /// Maximum allowed number of files in a single strongly connected component.
  /// When set, any larger SCC fails the run even with `--no-fail-on-cycle`.
  final int? maxSccSize;

  /// Whether layer violations make the run fail (exit code 1).
  final bool failOnLayerViolation;

  /// Human-readable problems found while loading the configuration
  /// (unparseable YAML, wrong value types, unknown keys, legacy names).
  final List<String> warnings;

  /// Path of the file the configuration was loaded from, if any.
  final String? sourcePath;

  /// Creates a configuration; usually built with [ArchGuardConfig.parse] or [ArchGuardConfig.load].
  const ArchGuardConfig({
    this.ignorePatterns = const [],
    this.layers = const {},
    this.preset,
    this.presetOnlyLayers = const {},
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
      rootPath: absRoot,
      source: sourceName!,
      sourcePath: sourceName.startsWith('pubspec.yaml')
          ? p.join(absRoot, 'pubspec.yaml')
          : p.join(absRoot, sourceName),
      warnings: warnings,
    );
  }

  /// Parses configuration from YAML text, as if read from [source] in the
  /// project at [rootPath]. Problems are reported in [ArchGuardConfig.warnings].
  static ArchGuardConfig parse(
    String yaml, {
    required String rootPath,
    String source = 'arch_guard.yaml',
  }) {
    final warnings = <String>[];
    Object? doc;
    try {
      doc = loadYaml(yaml);
    } catch (e) {
      warnings.add('$source: could not be parsed and was ignored ($e).');
    }
    if (doc is! Map) {
      if (doc != null) {
        warnings.add('$source: expected a YAML map at the top level.');
      }
      return ArchGuardConfig(warnings: warnings);
    }
    final absRoot = p.canonicalize(rootPath);
    return _parse(
      doc,
      rootPath: absRoot,
      source: source,
      sourcePath: p.join(absRoot, source),
      warnings: warnings,
    );
  }

  static ArchGuardConfig _parse(
    Map raw, {
    required String rootPath,
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

    String? preset;
    final layersMap = <String, LayerDefinition>{};
    final presetOnly = <String>{};
    final rawPreset = raw['preset'];
    if (rawPreset is String) {
      final presetLayers = LayerPresets.expand(
        rawPreset,
        rootPath: rootPath,
        warnings: warnings,
      );
      if (presetLayers == null) {
        warnings.add(
          '$source: unknown preset `$rawPreset` (expected one of: '
          '${LayerPresets.names.join(', ')}).',
        );
      } else {
        preset = rawPreset;
        layersMap.addAll(presetLayers);
        presetOnly.addAll(presetLayers.keys);
      }
    } else if (rawPreset != null) {
      warnings.add('$source: `preset` must be a preset name.');
    }

    final rawLayers = raw['layers'];
    if (rawLayers is Map) {
      rawLayers.forEach((key, val) {
        final name = key.toString();
        presetOnly.remove(name);
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
        var layer = LayerDefinition.fromYaml(name, {
          'patterns': val['patterns'] is List ? val['patterns'] : null,
          'allowed_imports': val['allowed_imports'] is List
              ? val['allowed_imports']
              : null,
        });
        // Overriding a preset layer: keys left out keep the preset's values.
        final base = layersMap[name];
        if (base != null) {
          layer = LayerDefinition(
            name: name,
            patterns: val['patterns'] is List ? layer.patterns : base.patterns,
            allowedImports: val['allowed_imports'] is List
                ? layer.allowedImports
                : base.allowedImports,
          );
        }
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
      preset: preset,
      presetOnlyLayers: presetOnly,
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

/// Untyped map as returned by `package:yaml`.
typedef DynamicMap = Map<dynamic, dynamic>;
