# arch_guard_lint

Shows [arch_guard](https://pub.dev/packages/arch_guard) rules as warnings on the offending `import` line, in VS Code, Android Studio / IntelliJ and `dart analyze` / `flutter analyze`.

| Warning | When |
| :--- | :--- |
| `layer_violation` | An import crosses a layer boundary that `allowed_imports` does not allow. |
| `forbidden_package` | An import uses a package or core library listed under `forbidden_packages`. |

## Install

Requires Dart 3.10 / Flutter 3.38 or later.

```yaml
# analysis_options.yaml
plugins:
  arch_guard_lint: ^0.1.0
```

Restart the Dart analysis server afterwards (in VS Code: *Dart: Restart Analysis Server*).

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

Circular dependencies need the whole project graph, so they are not checked in the IDE. Use the `arch_guard` CLI or `expectArchitecture()` from `package:arch_guard/testing.dart` for those.
