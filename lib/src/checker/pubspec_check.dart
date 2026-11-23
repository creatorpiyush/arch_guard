import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/config_model.dart';
import '../scanner/project_scanner.dart';
import '../scanner/pubspec_reader.dart';

/// A `dependencies:` entry that nothing imports, or that only tests import.
class DependencyProblem {
  /// Name of the package whose `pubspec.yaml` declares [dependency].
  final String package;

  /// Project-relative `/` path of that `pubspec.yaml`.
  final String pubspecPath;

  /// The declared dependency.
  final String dependency;

  /// `unused` (nothing imports it) or `misplaced` (only tests import it).
  final String kind;

  /// 1-based line of [dependency] in the `pubspec.yaml`, if known.
  final int? line;

  /// Creates a problem.
  const DependencyProblem({
    required this.package,
    required this.pubspecPath,
    required this.dependency,
    required this.kind,
    this.line,
  });

  /// What is wrong and how to fix it.
  String get rule => kind == 'misplaced'
      ? '`$dependency` is used only from tests; move it to dev_dependencies '
            'in $pubspecPath.'
      : '`$dependency` is under dependencies in $pubspecPath but nothing '
            'imports it. Remove it, or add it to pubspec_check: ignore.';

  /// Baseline key: `<pubspecPath>: <dependency> (<kind>)`.
  String get key => '$pubspecPath: $dependency ($kind)';

  /// JSON form used by the JSON exporter.
  Map<String, Object> toJson() => {
    'package': package,
    'pubspec': pubspecPath,
    'dependency': dependency,
    'kind': kind,
    'line': ?line,
    'rule': rule,
  };
}

/// The result of [PubspecCheck.run].
class PubspecCheckResult {
  /// Problems, sorted by pubspec path, then dependency.
  final List<DependencyProblem> problems;

  /// Packages that could not be checked, and unused `ignore:` entries.
  final List<String> warnings;

  /// Creates a result.
  const PubspecCheckResult(this.problems, this.warnings);
}

/// Finds `dependencies:` entries that no Dart file of their package imports
/// (unused), or that only test-like folders import (misplaced).
/// `dev_dependencies` are never checked.
class PubspecCheck {
  /// Folders whose imports count as real use.
  static const runtimeDirs = ['lib', 'bin', 'hook', 'web'];

  /// Folders whose imports count as test-only use.
  static const testDirs = [
    'test',
    'tool',
    'integration_test',
    'test_driver',
    'benchmark',
    'example',
  ];

  /// Dependencies used without a Dart import, never reported.
  static const builtInIgnores = {'cupertino_icons'};

  /// Checks the root package and, with [enableWorkspace], every workspace
  /// member (including members without `lib/`) under [projectRoot].
  static Future<PubspecCheckResult> run({
    required String projectRoot,
    required ArchGuardConfig config,
    bool enableWorkspace = true,
  }) async {
    final root = p.canonicalize(projectRoot);
    final warnings = <String>[];
    final packageDirs = <String>{
      if (File(p.join(root, 'pubspec.yaml')).existsSync()) '.',
      if (enableWorkspace)
        for (final pkg in PubspecReader.discoverWorkspacePackages(
          root,
          requireLib: false,
        ).values)
          pkg.packagePath,
      // Explicit workspace entries whose pubspec can't be read are not
      // discovered; list them so they get a warning instead of silence.
      if (enableWorkspace) ..._literalWorkspaceEntries(root),
    };
    final rootIncludes = _includes(root);
    final declaredAnywhere = <String>{};
    final problems = <DependencyProblem>[];

    for (final dir in packageDirs.toList()..sort()) {
      final pubspecPath = dir == '.' ? 'pubspec.yaml' : '$dir/pubspec.yaml';
      final pkgRoot = dir == '.' ? root : p.join(root, dir);
      final YamlMap pubspec;
      try {
        final doc = loadYaml(
          File(p.join(pkgRoot, 'pubspec.yaml')).readAsStringSync(),
        );
        if (doc is! YamlMap) throw const FormatException('not a map');
        pubspec = doc;
      } on Object catch (e) {
        warnings.add('pubspec_check: skipped $pubspecPath: ${_firstLine(e)}.');
        continue;
      }
      final name = pubspec['name']?.toString() ?? p.basename(pkgRoot);
      final deps = pubspec.nodes['dependencies'];
      if (deps is! YamlMap) continue;

      final declared = <String, int?>{};
      for (final MapEntry(:key, :value) in deps.nodes.entries) {
        final dep = (key as YamlNode).value.toString();
        declaredAnywhere.add(dep);
        if (value is YamlMap && value.containsKey('sdk')) continue;
        if (builtInIgnores.contains(dep) ||
            config.pubspecCheckIgnore.contains(dep) ||
            dep == name) {
          continue;
        }
        declared[dep] = key.span.start.line + 1;
      }
      if (declared.isEmpty) continue;

      final runtime = await _imports(pkgRoot, runtimeDirs);
      final tests = await _imports(pkgRoot, testDirs);
      final includes = {
        ...rootIncludes,
        ..._includes(pkgRoot),
        ..._usedByFlutterSection(pubspec),
      };
      for (final dep in declared.keys.toList()..sort()) {
        if (runtime.contains(dep) || includes.contains(dep)) continue;
        problems.add(
          DependencyProblem(
            package: name,
            pubspecPath: pubspecPath,
            dependency: dep,
            kind: tests.contains(dep) ? 'misplaced' : 'unused',
            line: declared[dep],
          ),
        );
      }
    }

    for (final dep in config.pubspecCheckIgnore.toList()..sort()) {
      if (!declaredAnywhere.contains(dep)) {
        warnings.add(
          'pubspec_check: ignore: `$dep` is not a dependency of any package.',
        );
      }
    }
    problems.sort((a, b) {
      final c = a.pubspecPath.compareTo(b.pubspecPath);
      return c != 0 ? c : a.dependency.compareTo(b.dependency);
    });
    return PubspecCheckResult(problems, warnings);
  }

  /// Packages imported or exported from [dirs] of the package at [pkgRoot],
  /// with no excludes. Files inside a nested package (a deeper folder with
  /// its own `pubspec.yaml`, such as an `example/` app) don't count.
  static Future<Set<String>> _imports(String pkgRoot, List<String> dirs) async {
    final scan = await ProjectScanner(
      rootPath: pkgRoot,
      scanDirs: dirs,
      enableWorkspace: false,
      useDefaultExcludes: false,
    ).scan();
    final nested = <String, bool>{};
    bool inNestedPackage(String file) {
      var dir = p.posix.dirname(file);
      while (dir != '.' && dir != '/') {
        if (nested.putIfAbsent(
          dir,
          () => File(p.join(pkgRoot, dir, 'pubspec.yaml')).existsSync(),
        )) {
          return true;
        }
        dir = p.posix.dirname(dir);
      }
      return false;
    }

    return {
      for (final i in scan.packageImports)
        if (!inNestedPackage(i.file)) i.package,
    };
  }

  /// Packages the `flutter:` section uses without a Dart import: federated
  /// plugin `default_package`s, `intl` with `generate: true` (gen-l10n), and
  /// `packages/<name>/` paths in `assets:` and `fonts:`.
  static Set<String> _usedByFlutterSection(YamlMap pubspec) {
    final flutter = pubspec['flutter'];
    if (flutter is! Map) return const {};
    String? packageOf(Object? path) =>
        path is String && path.startsWith('packages/')
        ? path.split('/')[1]
        : null;
    final platforms = (flutter['plugin'] is Map)
        ? (flutter['plugin'] as Map)['platforms']
        : null;
    final fonts = flutter['fonts'];
    final assets = flutter['assets'];
    return {
      if (flutter['generate'] == true) 'intl',
      if (platforms is Map)
        for (final platform in platforms.values)
          if (platform is Map && platform['default_package'] is String)
            platform['default_package'] as String,
      if (assets is List)
        for (final a in assets) ?packageOf(a is Map ? a['path'] : a),
      if (fonts is List)
        for (final family in fonts)
          if (family is Map && family['fonts'] is List)
            for (final font in family['fonts'] as List)
              if (font is Map) ?packageOf(font['asset']),
    };
  }

  /// Package names in `include: package:<name>/...` of the
  /// `analysis_options.yaml` in [dir] (a string or a list).
  static Set<String> _includes(String dir) {
    final file = File(p.join(dir, 'analysis_options.yaml'));
    if (!file.existsSync()) return const {};
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! Map) return const {};
      final include = doc['include'];
      final values = include is List ? include : [include];
      return {
        for (final v in values)
          if (v is String && v.startsWith('package:'))
            v.substring('package:'.length).split('/').first,
      };
    } on Object {
      return const {};
    }
  }

  /// Entries of the root `workspace:` list that are plain paths (no glob)
  /// to a folder with a `pubspec.yaml`.
  static Iterable<String> _literalWorkspaceEntries(String root) {
    try {
      final doc = loadYaml(
        File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
      );
      final entries = doc is Map ? doc['workspace'] : null;
      if (entries is! List) return const [];
      return [
        for (final e in entries)
          if (p.posix.normalize('$e'.replaceAll(r'\', '/')) case final path
              when !path.contains(RegExp(r'[*?\[\]{}]')) &&
                  File(p.join(root, path, 'pubspec.yaml')).existsSync())
            path,
      ];
    } on Object {
      return const [];
    }
  }

  static String _firstLine(Object e) {
    final text = e is YamlException
        ? e.message
        : e is FormatException
        ? e.message
        : '$e';
    return text.split('\n').first.trim().replaceFirst(RegExp(r'\.$'), '');
  }
}
