import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/config_model.dart';
import '../models/scan_result.dart';
import '../scanner/ignore_comments.dart';

/// One module: a folder matched by a `modules: roots` glob.
class Module {
  /// Module name: the folder's base name (`cart` for `lib/features/cart`).
  final String name;

  /// Folder of the module, as scanned paths spell it
  /// (`lib/features/cart`, or `packages/app/lib/features/cart` in a workspace).
  final String dir;

  /// The `modules: roots` glob that matched [dir].
  final String root;

  /// Creates a module named [name] at [dir], matched by [root].
  const Module(this.name, this.dir, this.root);
}

/// An import from one module into another that `modules:` does not allow.
class ModuleViolation {
  /// Path of the importing file.
  final String sourceFile;

  /// Path of the imported file.
  final String targetFile;

  /// Module [sourceFile] belongs to.
  final String sourceModule;

  /// Module [targetFile] belongs to.
  final String targetModule;

  /// Folder of [targetModule], used to spell out its public files.
  final String targetModuleDir;

  /// 1-based line of the directive in [sourceFile], if known.
  final int? line;

  /// Modules [sourceModule] may import (`modules: allowed`). Set only when
  /// [targetModule] is not among them; `null` when the file is private.
  final List<String>? allowedModules;

  /// `modules: public` globs, relative to a module folder.
  final List<String> publicPatterns;

  /// Creates a violation of [sourceModule] importing [targetModule].
  const ModuleViolation({
    required this.sourceFile,
    required this.targetFile,
    required this.sourceModule,
    required this.targetModule,
    required this.targetModuleDir,
    this.line,
    this.allowedModules,
    this.publicPatterns = const [],
  });

  /// Whether [sourceModule] may not import [targetModule] at all, rather
  /// than importing a private file of it.
  bool get notAllowed => allowedModules != null;

  /// The broken rule.
  String get rule {
    final allowed = allowedModules;
    if (allowed != null) {
      return allowed.isEmpty
          ? '`$sourceModule` may not import other modules.'
          : '`$sourceModule` may only import modules '
                '${allowed.map((m) => '`$m`').join(', ')}.';
    }
    final public = publicPatterns.map((g) => '$targetModuleDir/$g').join(', ');
    return 'Other modules may import `$targetModule` only through $public.';
  }

  /// How to resolve the violation.
  String get suggestion => notAllowed
      ? 'Move the shared code out of `$targetModule` into code outside every '
            'module, or, if intended, add `$targetModule` to '
            '`modules: allowed: $sourceModule`.'
      : 'Import a public file of `$targetModule` instead (a barrel in '
            '$targetModuleDir that exports what other modules need), or move '
            'the code out of `$targetModule`.';

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'sourceFile': sourceFile,
    'targetFile': targetFile,
    'sourceModule': sourceModule,
    'targetModule': targetModule,
    'line': ?line,
    'reason': notAllowed ? 'not_allowed' : 'private',
    'allowedModules': ?allowedModules,
  };

  @override
  String toString() =>
      '❌ Module Violation: [$sourceModule] $sourceFile'
      '${line != null ? ':$line' : ''} -> [$targetModule] $targetFile';
}

/// Checks imports between modules against the `modules:` rules: a module may
/// import another only through its public files, and only the modules its
/// `allowed` entry lists. Files outside every module are not restricted.
class ModuleValidator {
  /// Validates every edge in [result] against `config.modules`.
  static List<ModuleViolation> validate({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    if (config.modules == null) return const [];
    final check = checker(config);
    return [
      for (final edge in result.edges)
        if (!edge.ignored.contains(IgnoreComments.moduleViolation))
          ?check(edge.from, edge.to, line: edge.line),
    ];
  }

  /// Returns a function that checks one import of [to] by [from].
  static ModuleViolation? Function(String from, String to, {int? line}) checker(
    ArchGuardConfig config,
  ) {
    final modules = config.modules;
    if (modules == null) return (from, to, {line}) => null;
    final moduleOf = moduleResolver(config);
    final public = [for (final g in modules.public) Glob(g, context: p.posix)];

    return (from, to, {line}) {
      final source = moduleOf(from);
      final target = moduleOf(to);
      if (source == null || target == null || source.dir == target.dir) {
        return null;
      }
      final allowed = modules.allowed[source.name];
      final notAllowed = allowed != null && !allowed.contains(target.name);
      if (!notAllowed) {
        final inside = to
            .replaceAll('\\', '/')
            .substring(target.dir.length + 1);
        if (public.any((g) => g.matches(inside))) return null;
      }
      return ModuleViolation(
        sourceFile: from,
        targetFile: to,
        sourceModule: source.name,
        targetModule: target.name,
        targetModuleDir: target.dir,
        line: line,
        allowedModules: notAllowed ? allowed : null,
        publicPatterns: modules.public,
      );
    };
  }

  /// Returns a function mapping a file path to its module, or `null`.
  ///
  /// A folder is a module when a `roots` glob matches its path, or, in a
  /// workspace, its path from the first `lib/` segment (as layer patterns
  /// do). The outermost matching folder wins. Results are cached.
  static Module? Function(String path) moduleResolver(ArchGuardConfig config) {
    final roots = [
      for (final r in config.modules?.roots ?? const <String>[])
        (r, Glob(r, context: p.posix)),
    ];
    final cache = <String, Module?>{};
    return (path) => cache.putIfAbsent(path, () {
      final segments = path.replaceAll('\\', '/').split('/');
      final lib = segments.indexOf('lib');
      for (final start in {0, if (lib > 0) lib}) {
        // `end < length`: the file itself is never a module folder.
        for (var end = start + 1; end < segments.length; end++) {
          final candidate = segments.sublist(start, end).join('/');
          for (final (pattern, glob) in roots) {
            if (glob.matches(candidate)) {
              return Module(
                segments[end - 1],
                segments.sublist(0, end).join('/'),
                pattern,
              );
            }
          }
        }
      }
      return null;
    });
  }

  /// Modules found among the scanned files, keyed by folder.
  static Map<String, Module> modulesIn({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    final moduleOf = moduleResolver(config);
    final modules = <String, Module>{};
    for (final file in result.files.keys) {
      final m = moduleOf(file);
      if (m != null) modules[m.dir] = m;
    }
    return modules;
  }

  /// Problems with `modules:` that only the scan can show: roots that match
  /// no folder and `allowed` names that are not modules (likely typos).
  static List<String> warnings({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    final modules = config.modules;
    if (modules == null) return const [];
    final found = modulesIn(result: result, config: config).values;
    final roots = {for (final m in found) m.root};
    final names = {for (final m in found) m.name};
    final seen = <String>{};
    return [
      for (final r in modules.roots)
        if (!roots.contains(r))
          'modules: root `$r` matches no folder of the scanned files.',
      // With no module found, the root warning already says why; naming
      // every `allowed` entry too would only bury it.
      if (names.isNotEmpty)
        for (final MapEntry(:key, :value) in modules.allowed.entries)
          for (final name in [key, ...value])
            if (!names.contains(name) && seen.add(name))
              'modules: allowed names `$name`, which is not a module.',
    ];
  }
}
