import 'dart:convert';

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:arch_guard/arch_guard.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// arch_guard rules for one project, as the plugin sees them.
class ProjectRules {
  /// The configuration in effect.
  final ArchGuardConfig config;

  /// Checks one import against the layer rules.
  final LayerViolation? Function(String from, String to, {int? line})
  checkLayer;

  /// Checks one import against `forbidden_packages`.
  final PackageViolation? Function(String file, String uri, {int? line})
  checkPackage;

  final Folder _root;
  final Baseline? _baseline;
  final List<Glob> _ignore;

  ProjectRules._(this._root, this.config, this._baseline)
    : checkLayer = LayerValidator.checker(config),
      checkPackage = PackageValidator.checker(config),
      _ignore = [
        for (final g in config.ignorePatterns) Glob(g, context: p.posix),
      ];

  /// [absolutePath] relative to the config folder with `/` separators, or
  /// `null` when it lies outside that folder.
  String? relative(String absolutePath) {
    final ctx = _root.provider.pathContext;
    if (!ctx.isWithin(_root.path, absolutePath)) return null;
    return ctx.split(ctx.relative(absolutePath, from: _root.path)).join('/');
  }

  /// Whether [relativePath] matches the config's `ignore:` globs.
  bool isIgnored(String relativePath) =>
      _ignore.any((g) => g.matches(relativePath));

  /// Whether the baseline already lists [v].
  bool isKnownLayerViolation(LayerViolation v) =>
      _baseline?.layerViolations.contains(Baseline.violationKey(v)) ?? false;

  /// Whether the baseline already lists [v].
  bool isKnownPackageViolation(PackageViolation v) =>
      _baseline?.packageViolations.contains(Baseline.packageViolationKey(v)) ??
      false;

  // Keyed by provider so in-memory test providers never share entries.
  static final _cache = Expando<Map<String, (String, ProjectRules?)>>();

  /// Rules for the library in [context], or `null` when it is outside a
  /// package, outside `lib/`, or the project has no layer or package rules.
  static ProjectRules? of(RuleContext context) {
    if (!context.isInLibDir) return null;
    final packageRoot = context.package?.root;
    if (packageRoot == null) return null;
    final root = _configRoot(packageRoot);

    final configFile = _child(root, 'arch_guard.yaml');
    final baselineFile = _child(root, defaultBaselineFileName);
    int stamp(File f) => f.exists ? f.modificationStamp : -1;
    final pubspec = _child(root, 'pubspec.yaml');
    final key = '${stamp(configFile)}:${stamp(pubspec)}:${stamp(baselineFile)}';

    final byPath = _cache[root.provider] ??= {};
    final cached = byPath[root.path];
    if (cached != null && cached.$1 == key) return cached.$2;

    final rules = _load(root, baselineFile);
    byPath[root.path] = (key, rules);
    return rules;
  }

  static ProjectRules? _load(Folder root, File baselineFile) {
    final config = ArchGuardConfig.loadWith(root.path, (name) {
      final f = _child(root, name);
      return f.exists ? f.readAsStringSync() : null;
    });
    if (config.forbiddenPackages.isEmpty && config.layers.isEmpty) return null;

    Baseline? baseline;
    if (baselineFile.exists) {
      try {
        baseline = Baseline.fromJson(
          jsonDecode(baselineFile.readAsStringSync()),
        );
      } catch (_) {
        // A broken baseline is reported by the CLI; the plugin just ignores it.
      }
    }
    return ProjectRules._(root, config, baseline);
  }

  /// Nearest folder at or above [packageRoot] with an arch_guard config file,
  /// else [packageRoot] itself (which may have an `arch_guard:` pubspec key).
  static Folder _configRoot(Folder packageRoot) {
    for (Folder? f = packageRoot; f != null; f = f.isRoot ? null : f.parent) {
      if (_child(f, 'arch_guard.yaml').exists ||
          _child(f, 'dep_graph.yaml').exists) {
        return f;
      }
    }
    return packageRoot;
  }

  // `Folder.getFile` only exists from analyzer 14; this works on 8.4+.
  static File _child(Folder folder, String name) => folder.provider.getFile(
    folder.provider.pathContext.join(folder.path, name),
  );
}
