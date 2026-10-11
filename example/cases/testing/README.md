# Architecture tests (`expectArchitecture`)

Run the same checks as the CLI inside `dart test` or `flutter test`. [`test/architecture_test.dart`](test/architecture_test.dart) shows three tests:

- `expectArchitecture()` fails exactly when `arch_guard` would exit `1`.
- The returned `ArchAnalysis` lets you add your own assertions (here: no file imported by more than 5 others).
- `expectArchitecture(since: 'origin/main')` checks only files changed on the branch. It is skipped here, because it needs a git checkout.

## Try it

```bash
cd example/cases/testing
dart pub get
dart test
```

```text
00:00 +2 ~1: All tests passed!
```

In your project, add the dev dependency and copy the test:

```yaml
dev_dependencies:
  arch_guard: ^1.7.0
```

When a rule breaks (say a new `lib/domain/bad.dart` imports `data`), the test fails with every problem listed:

```text
arch_guard found 1 architecture problem(s):
  - Layer violation: lib/domain/bad.dart:1 (domain) imports lib/data/note_store.dart (data). `domain` may only import `domain`.
Fix them, or record them as known with `dart run arch_guard --update-baseline`.
```

Learn more: [Testing](https://creatorpiyush.github.io/arch_guard/testing.html)
