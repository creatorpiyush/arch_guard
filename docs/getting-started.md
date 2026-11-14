---
title: Getting started
description: Install arch_guard, generate a config, read your first report and keep the rules on every pull request.
---

# Getting started

Five minutes from install to an architecture check that runs on every pull request.

## 1. Install

Pick one. Both give you the same checks.

**With Dart** (Dart 3.8 or later, Flutter 3.32 or later):

```bash
dart pub add --dev arch_guard
```

This makes `dart run arch_guard` available in the project. Prefer a global command? Run `dart pub global activate arch_guard`, then call `arch_guard` directly.

**Without Dart** (Linux, macOS on Apple Silicon, Windows in Git Bash):

```bash
curl -fsSL https://creatorpiyush.github.io/arch_guard/install.sh | sh
```

This installs the release binary as `~/.local/bin/arch_guard`, after checking its SHA-256 checksum. See [Standalone binaries](cli.md#standalone-binaries) for options.

The library API, `expectArchitecture()` in tests and the IDE plugin need the Dart package. Other pages use the short form `arch_guard`.

## 2. Generate a config

```bash
dart run arch_guard init --dry-run   # preview
dart run arch_guard init             # write arch_guard.yaml
```

`init` looks at your folders and picks a [preset](presets.md): Clean Architecture, Riverpod, Bloc or feature-first. It writes the preset into `arch_guard.yaml` with the expanded layers as comments, so you can see what is checked, then scans the project once:

```text
# Layout: found domain/, data/, presentation/ folders.
preset: clean_architecture
...
First scan: 5 files
  core          1 file(s)
  domain        1 file(s)
  data          1 file(s)
  presentation  1 file(s)
  (no layer)    1 file(s), not checked
  1 layer violation(s), 0 circular dependency group(s)
```

No preset fits? `init` writes a commented template instead. Describe your layers yourself; see [Configuration](configuration.md).

## 3. Run the check

```bash
dart run arch_guard
```

The exit code tells you the result: `0` clean, `1` problems found, `2` the project could not be scanned, `64` bad flags. A failing report looks like this:

```text
[!] STRONGLY CONNECTED COMPONENTS (SCCs) DETECTED:

  Strongly Connected Component #1 (2 files)
    Representative Cycle Path:
    lib/widgets/nav.dart
    -> lib/screens/home.dart
    -> lib/widgets/nav.dart
    Suggested fix: remove lib/screens/home.dart:1 -> lib/widgets/nav.dart (breaks the cycle)

[!] LAYER BOUNDARY VIOLATIONS DETECTED (1):
  ❌ Layer Violation: [models] lib/models/user.dart:1 -> [services] lib/services/session_service.dart
     Rule: `models` may only import `models`.
```

A *strongly connected component* (SCC) is a group of files that import each other in a loop.

## 4. Fix, or accept what is there today

| Problem | Fix it in code | Or change the rule | Or accept it for now |
| :--- | :--- | :--- | :--- |
| Layer violation | Invert the dependency (an interface in the importing layer), or move the code | Add the layer to `allowed_imports` | Baseline, or an ignore comment |
| Cycle | Remove the import on the `Suggested fix:` line | – | Baseline, or an ignore comment |

An ignore comment accepts one import: put `// ignore: arch_guard_lint/layer_violation` (or `circular_dependency`, `forbidden_package`) on the line above it.

On an existing codebase you will usually find more than you want to fix today. Record them as known, and only new problems will fail:

```bash
dart run arch_guard --update-baseline   # writes arch_guard_baseline.json
git add arch_guard.yaml arch_guard_baseline.json
```

When you fix a known problem, the run tells you, so you can update the baseline and keep it from coming back. [How baselines work](ci.md#adopting-on-an-existing-codebase-baseline).

## 5. Keep it enforced

Pick one or more. They all read the same `arch_guard.yaml` and baseline, so they always agree.

**On every pull request.** Add `.github/workflows/architecture.yml`. The action posts one PR comment and keeps it up to date.

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
      - uses: creatorpiyush/arch_guard@v1.14.1
```

**In your tests.** `test/architecture_test.dart` fails `dart test` / `flutter test` exactly when the CLI would exit `1`.

```dart
import 'package:arch_guard/testing.dart';
import 'package:test/test.dart'; // or package:flutter_test/flutter_test.dart

void main() {
  test('architecture', () async {
    await expectArchitecture();
  });
}
```

**In your editor.** Warnings on the offending import, with quick fixes. Needs Dart 3.10 or later.

```yaml
# analysis_options.yaml
plugins:
  arch_guard_lint: ^0.3.1
```

## Next steps

- [Presets](presets.md): what each preset allows, with a typical violation and its fix.
- [Configuration](configuration.md): every key, forbidden packages, workspaces, unused files.
- [CI & hooks](ci.md): GitLab, pre-commit, `--since` for large repositories.
- [Troubleshooting](troubleshooting.md): when a result surprises you.
