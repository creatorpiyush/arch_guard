import 'dart:io';

import 'package:path/path.dart' as p;

import 'layer_definition.dart';

/// Predefined layer rules selected with `preset:` in the configuration.
///
/// Patterns use `lib/**/name/**`, so they match both layer-first layouts
/// (`lib/domain/...`) and feature-first ones (`lib/features/auth/domain/...`),
/// but not a workspace package that happens to be named `core` or `data`.
/// The first layer whose patterns match a file wins, so order matters.
class LayerPresets {
  static const cleanArchitecture = 'clean_architecture';
  static const featureFirst = 'feature_first';
  static const bloc = 'bloc';
  static const riverpod = 'riverpod';

  /// All preset names with a one-line description.
  static const descriptions = {
    cleanArchitecture:
        'core, domain, data and presentation layers; domain depends on nothing '
        'but core, presentation may not import data.',
    featureFirst:
        'one layer per folder in lib/features (or lib/modules); features may '
        'import only themselves and shared code (lib/core, lib/shared, lib/common).',
    bloc:
        'presentation -> business_logic (bloc/cubit) -> repository -> '
        'data_provider, with models usable everywhere.',
    riverpod:
        'presentation, application, domain and data layers as in the Riverpod '
        'app architecture; domain depends on nothing, data never sees the UI.',
  };

  static Iterable<String> get names => descriptions.keys;

  /// Folders searched, in order, for feature directories by [featureFirst].
  static const featureRoots = ['lib/features', 'lib/modules'];

  /// Folders treated as shared code by [featureFirst].
  static const sharedRoots = ['lib/core', 'lib/shared', 'lib/common'];

  /// Expands preset [name] into layer definitions for the project at
  /// [rootPath], or returns `null` if the name is unknown. Problems (such as
  /// no feature folders for [featureFirst]) are appended to [warnings].
  static Map<String, LayerDefinition>? expand(
    String name, {
    required String rootPath,
    List<String>? warnings,
  }) {
    switch (name) {
      case cleanArchitecture:
        return _layers([
          ('core', ['lib/**/core/**'], ['core']),
          ('domain', ['lib/**/domain/**'], ['core', 'domain']),
          ('data', ['lib/**/data/**'], ['core', 'domain', 'data']),
          (
            'presentation',
            ['lib/**/presentation/**', 'lib/**/ui/**'],
            ['core', 'domain', 'presentation'],
          ),
        ]);
      case bloc:
        return _layers([
          ('models', ['lib/**/models/**', 'lib/**/model/**'], ['models']),
          (
            'business_logic',
            [
              'lib/**/bloc/**',
              'lib/**/blocs/**',
              'lib/**/cubit/**',
              'lib/**/cubits/**',
            ],
            ['business_logic', 'repository', 'models'],
          ),
          (
            'repository',
            ['lib/**/repository/**', 'lib/**/repositories/**'],
            ['repository', 'data_provider', 'models'],
          ),
          (
            'data_provider',
            [
              'lib/**/data_provider/**',
              'lib/**/data_providers/**',
              'lib/**/api/**',
              'lib/**/clients/**',
            ],
            ['data_provider', 'models'],
          ),
          (
            'presentation',
            [
              'lib/**/view/**',
              'lib/**/views/**',
              'lib/**/pages/**',
              'lib/**/screens/**',
              'lib/**/widgets/**',
            ],
            ['presentation', 'business_logic', 'models'],
          ),
        ]);
      case riverpod:
        return _layers([
          ('domain', ['lib/**/domain/**'], ['domain']),
          ('data', ['lib/**/data/**'], ['data', 'domain']),
          (
            'application',
            ['lib/**/application/**'],
            ['application', 'domain', 'data'],
          ),
          (
            'presentation',
            ['lib/**/presentation/**'],
            ['presentation', 'application', 'domain', 'data'],
          ),
        ]);
      case featureFirst:
        return _featureFirst(rootPath, warnings);
    }
    return null;
  }

  static Map<String, LayerDefinition> _featureFirst(
    String rootPath,
    List<String>? warnings,
  ) {
    final features = <String, String>{}; // layer name -> folder
    for (final root in featureRoots) {
      final dir = Directory(p.join(rootPath, root));
      if (!dir.existsSync()) continue;
      final names =
          dir
              .listSync()
              .whereType<Directory>()
              .map((d) => p.basename(d.path))
              .where((n) => !n.startsWith('.'))
              .toList()
            ..sort();
      for (final name in names) {
        features['feature_$name'] = '$root/$name';
      }
      if (names.isNotEmpty) break;
    }

    if (features.isEmpty) {
      warnings?.add(
        'preset `$featureFirst` found no feature folders in '
        '${featureRoots.join(' or ')}.',
      );
    }

    return {
      'shared': LayerDefinition(
        name: 'shared',
        patterns: [for (final root in sharedRoots) '$root/**'],
        allowedImports: const ['shared'],
      ),
      for (final MapEntry(key: name, value: folder) in features.entries)
        name: LayerDefinition(
          name: name,
          patterns: ['$folder/**'],
          allowedImports: [name, 'shared'],
        ),
    };
  }

  static Map<String, LayerDefinition> _layers(
    List<(String, List<String>, List<String>)> specs,
  ) => {
    for (final (name, patterns, allowed) in specs)
      name: LayerDefinition(
        name: name,
        patterns: patterns,
        allowedImports: allowed,
      ),
  };
}
