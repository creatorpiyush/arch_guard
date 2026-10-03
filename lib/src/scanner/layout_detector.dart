import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/layer_presets.dart';

/// Result of guessing a project's architecture from its folder layout.
class LayoutDetection {
  /// Suggested preset name (see [LayerPresets]), or `null` if none fits.
  final String? preset;

  /// Human-readable explanation of why [preset] was chosen.
  final String reason;

  /// Creates a detection result.
  const LayoutDetection(this.preset, this.reason);
}

/// Guesses which [LayerPresets] preset fits a project, from the folder names
/// under its `lib/` directories and the packages it depends on.
class LayoutDetector {
  static const _skippedDirs = {
    'build',
    'test',
    'example',
    'android',
    'ios',
    'web',
    'macos',
    'windows',
    'linux',
    'node_modules',
  };

  /// Guesses the preset for the project at [rootPath].
  static LayoutDetection detect(String rootPath) {
    final libFolders = _libFolderNames(rootPath);
    final deps = _dependencyNames(rootPath);
    bool has(String name) => libFolders.contains(name);

    final cleanFolders = ['domain', 'data', 'presentation'].where(has).toList();
    final hasClean = has('domain') && (has('data') || has('presentation'));

    if (hasClean &&
        has('application') &&
        deps.any((d) => d.contains('riverpod'))) {
      return LayoutDetection(
        LayerPresets.riverpod,
        'found ${[...cleanFolders, 'application'].map((f) => '$f/').join(', ')} '
        'folders and a Riverpod dependency',
      );
    }
    if (hasClean) {
      return LayoutDetection(
        LayerPresets.cleanArchitecture,
        'found ${cleanFolders.map((f) => '$f/').join(', ')} folders',
      );
    }

    final blocFolders = [
      'bloc',
      'blocs',
      'cubit',
      'cubits',
    ].where(has).toList();
    if (blocFolders.isNotEmpty) {
      return LayoutDetection(
        LayerPresets.bloc,
        'found ${blocFolders.map((f) => '$f/').join(', ')} folders',
      );
    }

    for (final root in LayerPresets.featureRoots) {
      final dir = Directory(p.join(rootPath, root));
      if (dir.existsSync() &&
          dir.listSync().whereType<Directory>().isNotEmpty) {
        return LayoutDetection(
          LayerPresets.featureFirst,
          'found feature folders in $root/',
        );
      }
    }

    return const LayoutDetection(null, 'no common architecture layout found');
  }

  /// Names of all folders that sit somewhere below a `lib/` directory.
  static Set<String> _libFolderNames(String rootPath) {
    final names = <String>{};

    void walk(Directory dir, bool insideLib, int depth) {
      if (depth > 12) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entry in entries.whereType<Directory>()) {
        final name = p.basename(entry.path);
        if (name.startsWith('.') || _skippedDirs.contains(name)) continue;
        if (insideLib) names.add(name);
        walk(entry, insideLib || name == 'lib', depth + 1);
      }
    }

    walk(Directory(rootPath), false, 0);
    return names;
  }

  static Set<String> _dependencyNames(String rootPath) {
    final file = File(p.join(rootPath, 'pubspec.yaml'));
    if (!file.existsSync()) return const {};
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! Map) return const {};
      return {
        for (final key in ['dependencies', 'dev_dependencies'])
          if (doc[key] is Map) ...(doc[key] as Map).keys.map((k) => '$k'),
      };
    } catch (_) {
      return const {};
    }
  }
}
