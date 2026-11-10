import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/scan_result.dart';

/// Finds scanned files that no entry point reaches through imports, exports
/// or parts (`unused_files:` in the config).
class UnusedFiles {
  /// Entry-point globs that always apply, relative to the project root and to
  /// each workspace member. Each package's public library
  /// (`lib/<name>.dart`) and any `*_test.dart` are entry points too.
  static const defaultEntryPoints = [
    // main.dart and flavours (main_dev.dart), not lib/maintenance.dart.
    'lib/main.dart',
    'lib/main_*.dart',
    'bin/**',
    'test/**',
    'integration_test/**',
    'tool/**',
    'example/**',
  ];

  /// Returns the scanned files in [result] that no entry point reaches,
  /// sorted. Every edge counts, conditional or ignored, of any type.
  ///
  /// [entryPoints] are extra globs on project-relative `/` paths. When no
  /// scanned file is an entry point, `noEntryPoint` is true and `files` is
  /// empty, rather than reporting every file.
  static ({List<String> files, bool noEntryPoint}) find({
    required ScanResult result,
    List<String> entryPoints = const [],
  }) {
    final memberRoots = {
      for (final pkg in result.packages)
        if (pkg.packagePath != '.') '${pkg.packagePath}/',
    };
    Glob glob(String g) => Glob(g, context: p.posix);
    final defaults = [...defaultEntryPoints.map(glob), glob('**/*_test.dart')];
    final extra = entryPoints.map(glob).toList();
    final barrels = {
      'lib/${result.packageName}.dart',
      for (final pkg in result.packages) '${pkg.libPath}/${pkg.name}.dart',
    };
    // Defaults are matched relative to the project root and to the member
    // the file sits in, so `lib/features/test/x.dart` is no entry point.
    bool isEntry(String f) =>
        barrels.contains(f) ||
        extra.any((g) => g.matches(f)) ||
        [
          f,
          // Each folder prefix of f that is a member root (one lookup per
          // folder, not one per member).
          for (var i = f.indexOf('/'); i != -1; i = f.indexOf('/', i + 1))
            if (memberRoots.contains(f.substring(0, i + 1))) f.substring(i + 1),
        ].any((rel) => defaults.any((g) => g.matches(rel)));
    final queue = result.files.keys.where(isEntry).toList();
    if (queue.isEmpty) return (files: const [], noEntryPoint: true);

    final next = <String, List<String>>{};
    for (final e in result.edges) {
      (next[e.from] ??= []).add(e.to);
    }
    final seen = queue.toSet();
    while (queue.isNotEmpty) {
      for (final to in next[queue.removeLast()] ?? const <String>[]) {
        if (seen.add(to)) queue.add(to);
      }
    }
    return (
      files: [
        for (final f in result.files.keys)
          if (!seen.contains(f)) f,
      ]..sort(),
      noEntryPoint: false,
    );
  }
}
