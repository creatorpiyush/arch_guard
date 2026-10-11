---
title: IDE
---

# IDE warnings

Shows [arch_guard](https://pub.dev/packages/arch_guard) rules as warnings on the offending `import` line, in VS Code, Android Studio / IntelliJ and `dart analyze` / `flutter analyze`, with quick fixes.

| Warning | When | Quick fixes |
| :--- | :--- | :--- |
| `layer_violation` | An import crosses a layer boundary that `allowed_imports` does not allow. | Remove the import · Allow the import in the config |
| `forbidden_package` | An import uses a package or core library listed under `forbidden_packages`. | Remove the import |
| `circular_dependency` | This import closes a cycle among files in `lib/`. It is the one import whose removal breaks the cycle, or shrinks it the most. | Remove the import |

## Install

Requires Dart 3.10 / Flutter 3.38 or later.

```yaml
# analysis_options.yaml
plugins:
  arch_guard_lint: ^0.2.0
```

Restart the Dart analysis server afterwards (in VS Code: *Dart: Restart Analysis Server*).

## Quick fixes

Open the quick-fix menu on a warning (VS Code: `Ctrl+.` / `Cmd+.`).

- **Remove this import** (all three warnings): deletes the directive. For a conditional import, only the clause is removed. For example, `import 'a.dart' if (dart.library.io) 'b.dart'` becomes `import 'a.dart'`.
- **Allow layer `domain` to import `data`** (`layer_violation`): adds the imported layer to the importing layer's `allowed_imports`. It edits the file the config came from: `arch_guard.yaml`, the `arch_guard:` section of `pubspec.yaml`, or a legacy `dep_graph.yaml`.
  - If the layer comes from a preset, the fix writes an override that keeps the preset's list and adds the new layer.

The fixes run one at a time, never in bulk or through `dart fix`. Removing an import or loosening a rule should be your call. There is no "allow" fix for `forbidden_packages`: weakening a "never import this" rule should be a deliberate edit.

## Circular dependencies

`circular_dependency` uses the same cycle-breaking hint as the CLI. Each cycle gets **one** warning, on the import to remove:

```console
warning - lib/domain/user.dart:1:8 - This import closes a circular dependency of 2 files: lib/domain/user_service.dart -> lib/domain/user.dart -> lib/domain/user_service.dart. Removing it breaks the cycle. Move the code both files need into a third file, or invert the dependency. - circular_dependency
```

- It needs no `arch_guard.yaml`. If one exists, its `ignore:` globs apply. Generated files (`*.g.dart`, `*.freezed.dart`…) never count.
- It covers the files in this package's `lib/`. Cycles across workspace packages are found by the CLI.
- Cycles in `arch_guard_baseline.json` are not shown.
- After an edit elsewhere in `lib/`, the warning updates within about two seconds.

To turn it off:

```yaml
# analysis_options.yaml
plugins:
  arch_guard_lint:
    version: ^0.2.0
    diagnostics:
      circular_dependency: false
```

## How it works

- Rules come from the same `arch_guard.yaml` (or `pubspec.yaml` `arch_guard:` section) the CLI uses. The plugin looks for `arch_guard.yaml` in the package and its parent folders, so a workspace-root config works too.
- Only files under `lib/` are checked, minus the config's `ignore:` globs.
- Problems already in `arch_guard_baseline.json` are not shown, so enabling the plugin on an existing codebase doesn't fail `dart analyze`.
- Edits to `arch_guard.yaml` or the baseline take effect without a restart.

Suppress a single warning:

```dart
// ignore: arch_guard_lint/layer_violation
import '../data/repo.dart';
```
