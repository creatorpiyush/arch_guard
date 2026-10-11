# arch_guard examples

Each case is a small project with its own README. The README shows the config, the command and the real output. To run them, clone the repository:

```bash
git clone https://github.com/creatorpiyush/arch_guard
cd arch_guard
dart pub get
dart run arch_guard example/cases/cycles
```

In your own project, `dart pub add --dev arch_guard`, then `dart run arch_guard`. Or install it once with `dart pub global activate arch_guard`.

## I want to…

| …do this | Case | Key config / flag |
| :--- | :--- | :--- |
| Find circular imports and see which import to remove | [cycles](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/cycles) | `max_scc_size`, `--no-fail-on-cycle`, `--explain` |
| Stop one layer from importing another | [layers](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/layers) | `layers`, `fail_on_layer_violation`, `ignore` |
| Choose what is scanned (`bin/`, generated code), keep config in `pubspec.yaml` | [scan_options](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/scan_options) | `--scan-dir`, `--exclude`, `arch_guard:` in pubspec, `part` files, `--no-color` |
| Start from a ready-made architecture | [presets](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/presets) | `preset`, overriding preset layers, `arch_guard init` |
| Keep `dart:io`, `flutter` or any package out of some code | [forbidden_packages](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/forbidden_packages) | `forbidden_packages` (project and per layer) |
| Stop files from becoming hubs | [metrics](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/metrics) | `metrics: max_fan_in / max_fan_out / hotspots` |
| Control which packages of a monorepo depend on which | [workspace_rules](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/workspace_rules) | `workspace_rules` |
| Adopt on a codebase that already has problems | [baseline](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/baseline) | `--update-baseline`, `--baseline` |
| Check only what a branch changed | [since](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/since) | `--since origin/main` |
| Check architecture in `dart test` / `flutter test` | [testing](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/testing) | `expectArchitecture()` |
| Get HTML, Mermaid, DOT, JSON, SARIF or Markdown | [reports](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/reports) | `-f`, `--scope all`, `--offline` |
| See violations and cycles in the IDE as you type, with quick fixes | [arch_guard_lint example](https://github.com/creatorpiyush/arch_guard/tree/main/arch_guard_lint/example) | analyzer plugin |
| Run it in CI (GitHub Action, GitLab, pre-commit, lefthook, git hook) | [CI guide](https://creatorpiyush.github.io/arch_guard/ci.html) | `creatorpiyush/arch_guard@v1.8.0` |
| Use it as a library | [example.dart](https://github.com/creatorpiyush/arch_guard/blob/main/example/example.dart), run on [sample_project](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/sample_project) and [sample_workspace](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/sample_workspace) | `ArchAnalysis.run()`, validators, exporters |

## Exit codes

| Code | Meaning | Example |
| :---: | :--- | :--- |
| `0` | No problems (or only known ones in the baseline) | [testing](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/testing) |
| `1` | New problems found | every other case |
| `2` | Could not run: missing directory, invalid baseline, git error with `--since` | `dart run arch_guard example/cases/no_such_dir` |
| `64` | Invalid usage: unknown option, `--since` with `--update-baseline` | `dart run arch_guard --bogus` |

## The library in one call

```dart
import 'package:arch_guard/arch_guard.dart';

Future<void> main() async {
  final analysis = await ArchAnalysis.run(projectPath: '.');

  for (final cycle in analysis.cycles) {
    print(cycle.exampleChain.join(' -> '));
    final hint = cycle.scc?.suggestedBreak;
    if (hint != null) print('  Suggested fix: remove ${hint.describe()}');
  }

  // Exactly what would make `arch_guard` exit with 1.
  for (final failure in analysis.failures()) {
    print(failure);
  }
}
```

[example.dart](https://github.com/creatorpiyush/arch_guard/blob/main/example/example.dart) goes further, with every class in action:

- the scanner and the explainer
- the layer, package, metric and workspace validators
- layer coverage and preset detection
- baselines
- every exporter
- `CycleBreaker` and `GitChanges`
