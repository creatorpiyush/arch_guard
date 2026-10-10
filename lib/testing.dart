/// Architecture checks for your test suite.
///
/// ```dart
/// import 'package:arch_guard/testing.dart';
/// import 'package:test/test.dart'; // or flutter_test
///
/// void main() {
///   test('architecture', () async {
///     await expectArchitecture();
///   });
/// }
/// ```
///
/// Uses the project's `arch_guard.yaml` and `arch_guard_baseline.json`, and
/// fails exactly when the `arch_guard` CLI would exit with `1`.
library;

import 'src/analysis/arch_analysis.dart';

export 'src/analysis/arch_analysis.dart';

/// Thrown by [expectArchitecture] when the project breaks its rules.
class ArchitectureViolationException implements Exception {
  /// Most problems listed in [message]; the rest are counted.
  static const maxListed = 50;

  /// One line per problem (see [ArchAnalysis.failures]).
  final List<String> failures;

  /// The full analysis, for custom reporting.
  final ArchAnalysis analysis;

  /// Creates the exception for [failures] found by [analysis].
  const ArchitectureViolationException(this.failures, this.analysis);

  /// Human-readable summary, shown by the test runner.
  String get message {
    final b = StringBuffer(
      'arch_guard found ${failures.length} architecture problem(s):\n',
    );
    for (final f in failures.take(maxListed)) {
      b.writeln('  - $f');
    }
    if (failures.length > maxListed) {
      b.writeln('  … and ${failures.length - maxListed} more');
    }
    b.write(
      'Fix them, or record them as known with '
      '`dart run arch_guard --update-baseline`.',
    );
    return b.toString();
  }

  @override
  String toString() => message;
}

/// Runs arch_guard on [projectPath] and throws
/// [ArchitectureViolationException] if it finds problems.
///
/// Returns the [ArchAnalysis] for further assertions. Options mirror the CLI
/// flags (`--no-fail-on-cycle`, `--scan-dir`, `--exclude`, `--no-workspace`).
/// Throws [FormatException] if the baseline file exists but is invalid.
Future<ArchAnalysis> expectArchitecture({
  String projectPath = '.',
  bool failOnCycle = true,
  bool useBaseline = true,
  List<String> scanDirs = const ['lib'],
  List<String> exclude = const [],
  bool enableWorkspace = true,
}) async {
  final analysis = await ArchAnalysis.run(
    projectPath: projectPath,
    scanDirs: scanDirs,
    exclude: exclude,
    enableWorkspace: enableWorkspace,
    useBaseline: useBaseline,
  );
  final failures = analysis.failures(failOnCycle: failOnCycle);
  if (failures.isNotEmpty) {
    throw ArchitectureViolationException(failures, analysis);
  }
  return analysis;
}
