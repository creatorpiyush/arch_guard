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
| Start from a ready-made architecture | [presets](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/presets) | `preset`, `arch_guard init` |
| Keep `dart:io`, `flutter` or any package out of some code | [forbidden_packages](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/forbidden_packages) | `forbidden_packages` (project and per layer) |
| Stop files from becoming hubs | [metrics](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/metrics) | `metrics: max_fan_in / max_fan_out / hotspots` |
| Control which packages of a monorepo depend on which | [workspace_rules](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/workspace_rules) | `workspace_rules` |
| Adopt on a codebase that already has problems | [baseline](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/baseline) | `--update-baseline`, `--baseline` |
| Check only what a branch changed | [since](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/since) | `--since origin/main` |
| Check architecture in `dart test` / `flutter test` | [testing](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/testing) | `expectArchitecture()` |
| Get HTML, Mermaid, DOT, JSON, SARIF or Markdown | [reports](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/reports) | `-f`, `--scope all`, `--offline` |
| See violations in the IDE as you type | [arch_guard_lint example](https://github.com/creatorpiyush/arch_guard/tree/main/arch_guard_lint/example) | analyzer plugin |
| Run it in CI (GitHub Action, GitLab, pre-commit) | [CI guide](https://creatorpiyush.github.io/arch_guard/ci.html) | `creatorpiyush/arch_guard@v1.7.0` |
| Use it as a library | [example.dart](https://github.com/creatorpiyush/arch_guard/blob/main/example/example.dart) | `ArchAnalysis.run()`, validators, exporters |

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

[example.dart](https://github.com/creatorpiyush/arch_guard/blob/main/example/example.dart) goes further: scanning, layer, package, metric and workspace validators, the explainer, and exporters.
