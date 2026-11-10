---
name: arch-guard
description: Set up and use arch_guard to enforce architecture rules in a Dart or Flutter project - layer rules, forbidden packages, circular dependencies, baselines and CI. Use when the user asks to add arch_guard, check or enforce architecture, find circular imports, when an arch_guard report, test failure or `layer_violation` / `circular_dependency` warning needs fixing, when the user asks why one file or folder depends on another file or package, or which tests a branch's changes affect.
---

# arch_guard

arch_guard is a CLI and Dart library that fails the build when a file imports a layer it shouldn't, finds circular dependencies and draws the dependency graph. Docs: https://creatorpiyush.github.io/arch_guard/

## Set up in a project

Run these from the package root (the folder with `pubspec.yaml`). Requires Dart 3.8+ / Flutter 3.32+.

1. Install: `dart pub add --dev arch_guard` (Flutter projects: `flutter pub add --dev arch_guard`).
2. Preview the config: `dart run arch_guard init --dry-run`. It detects the layout and picks a preset: `clean_architecture`, `riverpod`, `bloc`, `feature_first`, or none.
3. Show the user the detected preset and why it was chosen. If it does not match how they describe their architecture, rerun with `--preset <name>`.
4. Write the config: `dart run arch_guard init`. It prints how many files fall into each layer, plus the violations and cycles found. If `arch_guard.yaml` already exists, read it and do not pass `--force` unless the user asks.
5. Check: `dart run arch_guard`. Exit codes: `0` clean, `1` problems found, `2` scan error, `64` bad flags.
6. If the project has existing problems, ask the user to choose:
   - fix them now (see below), or
   - record them as known with `dart run arch_guard --update-baseline` and commit `arch_guard_baseline.json`. After that, only new problems fail.
7. Offer the optional extras below. Add only the ones the user wants.

## Optional extras

- **Test:** create `test/architecture_test.dart`. It makes `dart test` / `flutter test` fail on the same problems as the CLI.

  ```dart
  import 'package:arch_guard/testing.dart';
  import 'package:test/test.dart'; // Flutter: package:flutter_test/flutter_test.dart

  void main() {
    test('architecture', () async {
      await expectArchitecture();
    });
  }
  ```

- **GitHub Actions:** add `.github/workflows/architecture.yml`. Use the latest release tag from https://github.com/creatorpiyush/arch_guard/releases.

  ```yaml
  name: Architecture
  on: [pull_request]
  permissions:
    contents: read
    pull-requests: write
  jobs:
    arch_guard:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: creatorpiyush/arch_guard@<latest tag>
  ```

  GitLab CI, pre-commit, lefthook and git hooks: https://creatorpiyush.github.io/arch_guard/ci.html
- **IDE warnings:** the `arch_guard_lint` analyzer plugin (Dart 3.10+). Setup: https://creatorpiyush.github.io/arch_guard/ide.html

## Fix what it reports

```text
❌ Layer Violation: [presentation] lib/features/auth/presentation/page.dart:3 -> [data] lib/features/auth/data/repo.dart
   Rule: `presentation` may only import `core`, `domain`, `presentation`.
```

Fix a layer violation in the code. Prefer these, in order:

1. Invert the dependency: declare an interface in the importing layer and implement it in the imported layer.
2. Move the code into a layer the importer may import.

```text
Suggested fix: remove lib/screens/home.dart:1 -> lib/widgets/nav.dart (breaks the cycle)
```

For a cycle, start with the import named on the `Suggested fix:` line. Move the code both files need into a third file, or invert the dependency. Never just delete the import and leave the code broken.

If the user wants to keep one import as it is, and neither a fix nor the baseline fits, add `// ignore: arch_guard_lint/<code>` on the line above it (`layer_violation`, `forbidden_package` or `circular_dependency`). The CLI, CI and the IDE all honour it. Use it last, and ask first.

```text
[!] Unused files (1): no entry point imports these, directly or indirectly.
  lib/old/legacy.dart
```

For an unused file, check that nothing outside the scan uses it: code generation, reflection, `bin/` or `test/` when they are not scanned. Then ask the user before deleting it. If it is used, add the file that uses it under `unused_files: entry_points`.

To see why one file is in a cycle, run `dart run arch_guard --explain <file>`. To find where a forbidden import or layer violation comes from, run `dart run arch_guard why <from> <to>` (for example `why lib/domain flutter`); it prints the shortest import chain with line numbers, and exits `1` when there is none. On a branch, run `dart run arch_guard --since origin/main` to report only problems in changed files. While refactoring, a human can keep `dart run arch_guard --watch` open; agents should run one-shot checks instead, because `--watch` never exits on its own.

## Rules

- Do not add a layer to `allowed_imports`, remove a `forbidden_packages` entry, raise `max_fan_in` / `max_fan_out` / `max_scc_size`, set `unused_files: fail: false`, or run `--update-baseline` to make a failure go away. Each weakens the user's rules. Ask first.
- When a baseline is in use and the report says known problems are fixed, tell the user. Suggest `--update-baseline` so they cannot return.
- After a fix, rerun `dart run arch_guard` and confirm exit code `0` before you report the fix as done.

## More commands

- Interactive graph: `dart run arch_guard -f html -o build/reports`, then open `build/reports/dependency_graph.html`.
- Mermaid diagram for a README or PR: `dart run arch_guard -f mermaid -o build/reports`.
- Tests a branch can affect: `dart run arch_guard affected --since origin/main` prints one test file per line (`--print files` or `--print packages` for other lists, `--json` for all). Empty output means no tests are affected; do not pass empty output to `dart test`, which would run every test.
- Machine-readable report: `dart run arch_guard -f json -o build/reports`.
- Config reference (every key, workspaces, `forbidden_packages`, metric limits): https://creatorpiyush.github.io/arch_guard/configuration.html
