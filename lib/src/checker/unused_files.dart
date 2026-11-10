import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/scan_result.dart';

/// Finds scanned files that no entry point reaches through imports, exports
/// or parts (`unused_files:` in the config).
class UnusedFiles {
  /// Entry-point globs that always apply, before `unused_files: entry_points`.
  /// Each package's public barrel (`lib/<name>.dart`) is an entry point too.
  static const defaultEntryPoints = [
    'lib/main*.dart',
    '**/lib/main*.dart',
    'bin/**',
    '**/bin/**',
    'test/**',
    '**/test/**',
    'tool/**',
    'example/**',
    '**/*_test.dart',
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
    final globs = [
      for (final g in [...defaultEntryPoints, ...entryPoints])
        Glob(g, context: p.posix),
    ];
    final barrels = {
      'lib/${result.packageName}.dart',
      for (final pkg in result.packages) '${pkg.libPath}/${pkg.name}.dart',
    };
    final queue = [
      for (final f in result.files.keys)
        if (barrels.contains(f) || globs.any((g) => g.matches(f))) f,
    ];
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
