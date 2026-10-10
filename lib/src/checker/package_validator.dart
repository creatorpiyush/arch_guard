import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/config_model.dart';
import '../models/scan_result.dart';
import 'layer_validator.dart';

/// An import of a package or core library that `forbidden_packages` rules out.
class PackageViolation {
  /// Path of the importing file.
  final String sourceFile;

  /// The URI as written in the directive.
  final String uri;

  /// Package name (`flutter`) or core library (`dart:io`) that was imported.
  final String package;

  /// The `forbidden_packages` entry that matched (may be a glob).
  final String pattern;

  /// Layer whose rule was broken, or `null` for a project-wide rule.
  final String? layer;

  /// 1-based line of the directive in [sourceFile], if known.
  final int? line;

  /// Creates a violation of [sourceFile] importing [uri].
  const PackageViolation({
    required this.sourceFile,
    required this.uri,
    required this.package,
    required this.pattern,
    this.layer,
    this.line,
  });

  /// The broken rule, e.g. "Layer `domain` may not import `flutter` ...".
  String get rule => layer == null
      ? '`$package` is forbidden in this project '
            '(forbidden_packages: `$pattern`).'
      : 'Layer `$layer` may not import `$package` '
            '(forbidden_packages: `$pattern`).';

  /// How to resolve the violation.
  String get suggestion => layer == null
      ? 'Remove the import, or, if `$package` is now allowed, remove '
            '`$pattern` from the top-level `forbidden_packages`.'
      : 'Depend on an interface declared in `$layer` and implement it in a '
            'layer that may use `$package`, or, if this is intended, remove '
            '`$pattern` from the `forbidden_packages` of `$layer`.';

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'sourceFile': sourceFile,
    'uri': uri,
    'package': package,
    'pattern': pattern,
    'layer': ?layer,
    'line': ?line,
  };

  @override
  String toString() =>
      '❌ Forbidden Package: ${layer != null ? '[$layer] ' : ''}'
      '$sourceFile${line != null ? ':$line' : ''} -> $uri';
}

/// Checks `package:` and `dart:` imports against `forbidden_packages` rules.
class PackageValidator {
  /// Validates every [ScanResult.packageImports] entry against [config].
  static List<PackageViolation> validate({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    final check = checker(config);
    return [
      for (final i in result.packageImports)
        ?check(i.file, i.uri, line: i.line),
    ];
  }

  /// Returns a function that checks one directive of [file] importing [uri].
  ///
  /// Callers must skip imports of [file]'s own package themselves, because
  /// only they know which package [file] belongs to.
  static PackageViolation? Function(String file, String uri, {int? line})
  checker(ArchGuardConfig config) {
    // posix context: `dart:io` must never be read as a Windows drive path.
    List<(String, Glob)> compile(List<String> entries) => [
      for (final e in entries) (e, Glob(e, context: p.posix)),
    ];
    final project = compile(config.forbiddenPackages);
    final byLayer = {
      for (final l in config.layers.values)
        if (l.forbiddenPackages.isNotEmpty)
          l.name: compile(l.forbiddenPackages),
    };
    final layerOf = byLayer.isEmpty
        ? null
        : LayerValidator.layerResolver(config);

    String? match(List<(String, Glob)> globs, String package) {
      for (final (entry, glob) in globs) {
        if (glob.matches(package)) return entry;
      }
      return null;
    }

    return (file, uri, {line}) {
      final package = PackageImport.packageOf(uri);
      if (package == null) return null;

      final projectHit = match(project, package);
      if (projectHit != null) {
        return PackageViolation(
          sourceFile: file,
          uri: uri,
          package: package,
          pattern: projectHit,
          line: line,
        );
      }

      final layer = layerOf?.call(file);
      final globs = layer == null ? null : byLayer[layer];
      final layerHit = globs == null ? null : match(globs, package);
      if (layerHit == null) return null;
      return PackageViolation(
        sourceFile: file,
        uri: uri,
        package: package,
        pattern: layerHit,
        layer: layer,
        line: line,
      );
    };
  }
}
