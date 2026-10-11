import 'package:arch_guard/testing.dart';
import 'package:test/test.dart';

void main() {
  // Fails exactly when `dart run arch_guard` would exit with 1.
  test('architecture', () async {
    await expectArchitecture();
  });

  // The returned ArchAnalysis lets you add your own rules.
  test('no file is imported by more than 5 others', () async {
    final analysis = await expectArchitecture();
    expect(analysis.fileMetrics.where((m) => m.fanIn > 5), isEmpty);
  });

  // A project that breaks its rules: the exception lists every problem.
  test('reports violations', () async {
    await expectLater(
      expectArchitecture(projectPath: '../layers'),
      throwsA(
        isA<ArchitectureViolationException>().having(
          (e) => e.analysis.layerViolations,
          'layerViolations',
          hasLength(1),
        ),
      ),
    );
  });

  // Known problems in the baseline pass, unless useBaseline is false.
  test('baseline', () async {
    Future<List<String>> failures({required bool useBaseline}) async {
      try {
        await expectArchitecture(
          projectPath: '../baseline',
          useBaseline: useBaseline,
        );
        return [];
      } on ArchitectureViolationException catch (e) {
        return e.failures;
      }
    }

    // Only the new layer violation; the recorded cycle is known.
    expect(await failures(useBaseline: true), hasLength(1));
    // Without the baseline, the cycle fails too.
    expect(await failures(useBaseline: false), hasLength(2));
  });

  // In a large repo: only problems in files changed on this branch.
  // Needs git and the base branch fetched.
  test('changed files only', () async {
    await expectArchitecture(since: 'origin/main');
  }, skip: 'needs a git checkout with origin/main');
}
