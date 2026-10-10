---
title: Testing
---

# Testing

Run the architecture rules inside your test suite, so `dart test` and `flutter test` fail when a change breaks them. No separate CI step is needed.

## In a Dart or Flutter test

```yaml
# pubspec.yaml
dev_dependencies:
  arch_guard: ^1.5.0
```

```dart
// test/architecture_test.dart
import 'package:arch_guard/testing.dart';
import 'package:test/test.dart'; // or package:flutter_test/flutter_test.dart

void main() {
  test('architecture', () async {
    await expectArchitecture();
  });
}
```

`expectArchitecture()` reads the same `arch_guard.yaml` and `arch_guard_baseline.json` as the CLI. It fails exactly when `arch_guard` would exit with `1`, and the failure lists every problem:

```text
arch_guard found 1 architecture problem(s):
  - Layer violation: lib/domain/user.dart:1 (domain) imports lib/data/repo.dart (data). `domain` may not import other layers.
Fix them, or record them as known with `dart run arch_guard --update-baseline`.
```

It works with any test runner and adds no test dependencies of its own.

## Options

| Parameter | Default | Same as |
| :--- | :--- | :--- |
| `projectPath` | `'.'` (the package root under `dart test` / `flutter test`) | `arch_guard <path>` |
| `failOnCycle` | `true` | `--no-fail-on-cycle` when `false` |
| `useBaseline` | `true` | Set `false` to fail on known problems too |
| `scanDirs` | `['lib']` | `--scan-dir` |
| `exclude` | `[]` | `--exclude` |
| `enableWorkspace` | `true` | `--no-workspace` when `false` |

## Custom assertions

`expectArchitecture()` returns the `ArchAnalysis`. You can also run one directly and assert what you like:

```dart
final a = await ArchAnalysis.run();
expect(a.cycles.where((c) => c.files.length > 3), isEmpty);
expect(a.packageViolations, isEmpty);
```

## Baselines

With a baseline file, known problems pass and only new ones fail, the same as in CI. Pass `useBaseline: false` for a strict test that fails on every problem.

## Test or CI step?

Both read the same configuration. A test gives feedback locally as soon as you run the suite. The [GitHub Action](ci.md) adds PR comments, job summaries and SARIF for Code Scanning. Many projects use both.
