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

  // In a large repo: only problems in files changed on this branch.
  // Needs git and the base branch fetched.
  test('changed files only', () async {
    await expectArchitecture(since: 'origin/main');
  }, skip: 'needs a git checkout with origin/main');
}
