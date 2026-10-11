# arch_guard

[![pub version](https://img.shields.io/pub/v/arch_guard.svg)](https://pub.dev/packages/arch_guard)
[![pub points](https://img.shields.io/pub/points/arch_guard)](https://pub.dev/packages/arch_guard/score)
[![CI](https://github.com/creatorpiyush/arch_guard/actions/workflows/verify.yml/badge.svg)](https://github.com/creatorpiyush/arch_guard/actions/workflows/verify.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Keep your Dart and Flutter architecture the way you designed it.** arch_guard fails the build when a file imports a layer it shouldn't, finds circular dependencies, and draws your dependency graph, in the terminal, in pre-commit hooks and in CI.

![Interactive dependency graph showing two circular dependency groups](https://raw.githubusercontent.com/creatorpiyush/arch_guard/main/docs/images/graph.png)

```bash
dart pub add --dev arch_guard
dart run arch_guard init     # detects your layout and writes arch_guard.yaml
dart run arch_guard          # checks the project
```

📖 **Documentation: [creatorpiyush.github.io/arch_guard](https://creatorpiyush.github.io/arch_guard/)**

---

## Features

- 🛡️ **Layer rules.** Say which layers may import which (`domain` must not import `data`); every violation shows the import line and the rule it breaks.
- 🚫 **Forbidden packages.** Keep `flutter`, `dart:io` or any package out of a layer (or the whole project), with globs like `firebase_*`.
- 🏢 **Workspace rules.** In a monorepo, say which packages may depend on which: `apps/*` may use `packages/*`, never the reverse.
- 📏 **Metric limits and hotspots.** `max_fan_out` / `max_fan_in` stop files from becoming hubs; reports list the most coupled files.
- ⚡ **Presets and `init`.** `clean_architecture`, `riverpod`, `bloc` and `feature_first` presets; `arch_guard init` detects which one fits your project.
- 🔁 **Circular dependencies.** Tarjan's algorithm finds every group of files that import each other, with fan-in/fan-out, instability and hub metrics.
- 📌 **Baselines for existing code.** Record today's problems once; CI then fails only on *new* ones.
- 🎯 **`--since origin/main`.** Report only problems touching files changed on the branch.
- 🩹 **Cycle-breaking hints.** Each cycle names the one import to remove to break it.
- 🧪 **Architecture tests.** `await expectArchitecture();` in `dart test` / `flutter test` runs the same checks. See [Testing](https://creatorpiyush.github.io/arch_guard/testing.html).
- 💡 **IDE warnings.** The `arch_guard_lint` analyzer plugin underlines layer violations and forbidden imports as you type. See [IDE](https://creatorpiyush.github.io/arch_guard/ide.html).
- 🤖 **CI-ready.** A GitHub Action that comments on PRs, SARIF for GitHub Code Scanning, Markdown job summaries, pre-commit hooks, standalone binaries.
- 🎨 **Graphs.** Interactive HTML (works offline), Mermaid, Graphviz DOT and JSON.
- 🏢 **Workspaces and monorepos.** Dart workspaces and Melos-style `packages/`/`apps/` repos, including cycles across packages.
- 🔍 **`--explain <file>`.** Why is this file in a cycle? What does it import and what imports it?

**Examples:** a small, runnable project for each feature, with the command and its real output. See [example/example.md](https://github.com/creatorpiyush/arch_guard/blob/main/example/example.md).

## Why arch_guard?

| | arch_guard | [DCM](https://dcm.dev) | [import_lint](https://pub.dev/packages/import_lint) | [lakos](https://pub.dev/packages/lakos) |
| :--- | :---: | :---: | :---: | :---: |
| Price | Free, MIT | Free tier (1 seat, up to 50k LOC); paid plans | Free, MIT | Free, MIT |
| Import / layer rules | ✅ layers with `allowed_imports`, plus package-level `workspace_rules` | ✅ `avoid-banned-imports` rule | ✅ `target` / `from` rules | – |
| Ready-made architecture presets + `init` | ✅ | – | – | – |
| Circular dependency detection | ✅ with metrics | – | – | ✅ |
| Baseline for legacy code | ✅ | ✅ | – | – |
| Dependency graph output | HTML, Mermaid, DOT, JSON | DOT (`analyze-structure`) | – | DOT, JSON |
| PR comment / SARIF / GitHub Action | ✅ | CI integrations on paid plans | – | – |
| Warnings in the IDE | ✅ (`arch_guard_lint` analyzer plugin) | ✅ | ✅ (analyzer plugin) | – |

DCM is a full linting suite with hundreds of rules; import_lint shows import rules right in your editor; lakos focuses on graph metrics. arch_guard is built for one job: making architecture rules easy to adopt, including on a large existing codebase, and enforced on every pull request. *Comparison based on each tool's public documentation in October 2026; corrections welcome.*

---

## Installation

Requires Dart SDK 3.8 or later (Flutter 3.32 or later).

```bash
dart pub add --dev arch_guard          # as a dev dependency: dart run arch_guard
dart pub global activate arch_guard    # or globally: arch_guard
```

No Dart SDK? Prebuilt binaries for Linux (x64, arm64), macOS (Apple Silicon) and Windows (x64) are attached to every [GitHub Release](https://github.com/creatorpiyush/arch_guard/releases), with SHA-256 checksums.

## Configuration

`arch_guard init` writes `arch_guard.yaml` for you. The simplest config is a preset:

```yaml
# arch_guard.yaml
preset: clean_architecture
```

| Preset | Layers | Main rules |
| :--- | :--- | :--- |
| `clean_architecture` | `core`, `domain`, `data`, `presentation` | `domain` imports only `core`; `presentation` may not import `data`. |
| `riverpod` | `domain`, `data`, `application`, `presentation` | `domain` imports nothing else; `data` never imports `application` or `presentation`. |
| `bloc` | `models`, `business_logic`, `repository`, `data_provider`, `presentation` | UI → bloc/cubit → repository → data provider; `models` everywhere. |
| `feature_first` | `shared` + one `feature_<name>` per folder in `lib/features` | A feature imports only itself and `shared` (`lib/core`, `lib/shared`, `lib/common`). |

Adjust a preset by listing only what changes, or define every layer yourself:

```yaml
preset: clean_architecture
ignore:
  - "**/*.mocks.dart"
max_scc_size: 5            # optional: fail when a cycle group grows beyond 5 files
layers:
  presentation:
    allowed_imports: [core, domain, presentation, data]   # allow UI -> data
  di:
    patterns: ["lib/di/**"]
    allowed_imports: [core, domain, data, presentation, di]
```

The [presets guide](https://creatorpiyush.github.io/arch_guard/presets.html) has a recipe for each architecture, and the [configuration reference](https://creatorpiyush.github.io/arch_guard/configuration.html) covers every key and how workspaces are matched.

## Reading the report

![Terminal report with two cycles and a layer violation](https://raw.githubusercontent.com/creatorpiyush/arch_guard/main/docs/images/terminal.png)

```text
❌ Layer Violation: [presentation] lib/features/auth/presentation/page.dart:3 -> [data] lib/features/auth/data/repo.dart
   Rule: `presentation` may only import `core`, `domain`, `presentation`.
```

To fix a violation, invert the dependency (an interface in the importing layer, implemented by the imported one), move the code to a layer it may import, or, if the dependency is intended, add the layer to `allowed_imports`.

```text
Strongly Connected Component #1 (2 files)
  Representative Cycle Path:
  lib/widgets/nav.dart
  -> lib/screens/home.dart
  -> lib/widgets/nav.dart
  Suggested fix: remove lib/screens/home.dart:1 -> lib/widgets/nav.dart (breaks the cycle)
```

Each cycle comes with a `Suggested fix:` line naming the one import whose removal breaks it, or, when no single import does, the one that shrinks it most.

## Adopting on an existing codebase

```bash
arch_guard --update-baseline        # writes arch_guard_baseline.json
git add arch_guard_baseline.json
```

From then on only *new* cycles and layer violations fail the run. When known problems are fixed, arch_guard tells you, so you can update the baseline and keep them from coming back. [More about baselines](https://creatorpiyush.github.io/arch_guard/ci.html#adopting-on-an-existing-codebase-baseline).

## CI

```yaml
# .github/workflows/architecture.yml
name: Architecture
on: [pull_request]

permissions:
  contents: read
  pull-requests: write     # PR comment

jobs:
  arch_guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: creatorpiyush/arch_guard@v1.7.1
```

The action downloads a checksum-verified binary, posts one PR comment it keeps up to date, and can upload SARIF to GitHub Code Scanning. GitLab CI, pre-commit, lefthook and plain git hooks are covered in the [CI & hooks guide](https://creatorpiyush.github.io/arch_guard/ci.html).

## Command line

```bash
arch_guard [path] [options]
arch_guard . -f html -o build/reports                      # interactive graph
arch_guard . --explain lib/services/auth_service.dart      # one file's dependencies
arch_guard . -f sarif -f markdown -o build/reports         # for CI
```

| Exit code | Meaning |
| :---: | :--- |
| `0` | No cycles, layer violations or forbidden imports (or none new, with a baseline). |
| `1` | Cycles, layer violations or forbidden package imports found. |
| `2` | Scan error: missing directory, unreadable project or invalid baseline. |
| `64` | Invalid flags or arguments. |

All flags, output formats and the Dart API are in the [CLI reference](https://creatorpiyush.github.io/arch_guard/cli.html) and [API guide](https://creatorpiyush.github.io/arch_guard/api.html).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and checks, and [ARCHITECTURE.md](ARCHITECTURE.md) for how the code is organised.

## License

[MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party software attributions.
