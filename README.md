# arch_guard

A pub.dev-ready CLI tool and Dart library for static architecture analysis, enforcing **Clean Architecture layer boundaries**, detecting circular dependencies using **Tarjan's Strongly Connected Components (SCC) algorithm**, computing architectural coupling metrics, and exporting visual graph outputs (Terminal text, JSON, Mermaid `.mmd`, Graphviz `.dot`, and a rich interactive HTML centerpiece).

---

## Features

- 🛡️ **Clean Architecture Layer Validation**: Enforce directional rules (e.g. `domain` cannot import `presentation` or `data`) configured via `arch_guard.yaml` or `pubspec.yaml`.
- 🚀 **High-Performance Concurrent Scanning**: Bounded parallel async scanner (`Future.wait` batching) designed for 1,000+ file codebases.
- 📊 **Tarjan's SCC Severity Metrics**: Computes internal edge density, average Fan-In/Fan-Out, Instability ($I$), and dependency hub identification per SCC.
- 🔍 **CLI File Explainer (`--explain`)**: Interactively inspect incoming/outgoing dependencies and SCC membership for any specific file.
- 🏢 **Monorepo & Dart Workspace Auto-Discovery**: Automatically discovers member packages in Dart 3.6+ workspaces (`workspace: [...]`) or Melos repositories (`packages/*`, `apps/*`), mapping cross-package cycles.
- 🎨 **Multi-Format Exporters**:
  - **Interactive Centerpiece HTML**: Dark mode, Vis-network rendering with physics stabilization freeze, `--scope cycles` scalability, and `--offline` air-gapped support.
  - **Mermaid.js Diagram (`.mmd`)**: Native markdown diagrams ready for GitHub/GitLab PRs.
  - **JSON Data Report (`.json`)**: Machine-readable payload for CI/CD dashboards.
  - **Graphviz DOT (`.dot`)**: Subgraph-clustered DOT format for `dot -Tsvg`.
  - **SARIF (`.sarif`)**: Code-scanning results pointing at the offending import line.
  - **Markdown (`.md`)**: New problems plus the cycle graph, for PR comments.
- 📌 **Baselines for legacy code**: Record today's problems once with `--update-baseline`; CI then fails only on *new* cycles and layer violations.
- 🔎 **SARIF & PR-ready Markdown**: `-f sarif` for GitHub Code Scanning and SARIF viewers, `-f markdown` for pull request comments and job summaries.
- 🤖 **GitHub Action & pre-commit hook**: One step in a workflow, or one entry in `.pre-commit-config.yaml`.
- 💻 **Pub.dev Ready & Flexible CLI**: Configurable flags, exit codes for CI/CD pipelines (`0`, `1`, `2`, `64`), and a clear programmatic Dart API.

---

## Installation

Requires Dart SDK 3.8 or later (Flutter 3.32 or later).

Add as a dev dependency in your `pubspec.yaml` or install globally via pub:

```bash
dart pub add --dev arch_guard
dart pub global activate arch_guard
```

Then generate a starter configuration. `init` recognises Clean Architecture, Riverpod, Bloc and feature-first layouts and shows what the first scan finds:

```bash
dart run arch_guard init
```

Or run directly using `dart run` in any project or monorepo directory:

```bash
dart run arch_guard [path] [options]
```

### Standalone binaries (no Dart SDK needed)

Prebuilt executables for Linux (x64, arm64), macOS (Apple Silicon) and Windows (x64) are attached to every [GitHub Release](https://github.com/creatorpiyush/arch_guard/releases), along with a `SHA256SUMS.txt` file for checksum verification:

```bash
# Example: Linux x64 in CI
curl -fsSL -o arch_guard https://github.com/creatorpiyush/arch_guard/releases/latest/download/arch_guard-linux-x64
chmod +x arch_guard
./arch_guard . --format mermaid
```

---

## Configuration (`arch_guard.yaml` or `pubspec.yaml`)

The quickest start is `arch_guard init` (see [Layer presets](#layer-presets)). To write the rules yourself, define layers and ignore patterns in `arch_guard.yaml` at your project root:

```yaml
# arch_guard.yaml
ignore:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
  - "**/*.mocks.dart"

fail_on_layer_violation: true

# Optional: fail when any circular-dependency group grows beyond N files,
# even with --no-fail-on-cycle (useful for ratcheting down legacy cycles).
max_scc_size: 5

layers:
  domain:
    patterns:
      - "**/domain/**"
    allowed_imports:
      - "domain"

  presentation:
    patterns:
      - "**/presentation/**"
    allowed_imports:
      - "presentation"
      - "domain"

  data:
    patterns:
      - "**/data/**"
    allowed_imports:
      - "data"
      - "domain"
```

Or configure under `arch_guard:` in `pubspec.yaml`.

Configuration problems are reported as warnings on stderr rather than silently ignored: unparseable YAML, unknown keys, wrongly typed values, layers whose patterns match no files, `allowed_imports` that name unknown layers, and files that belong to no layer (and so are never checked). The legacy `dep_graph.yaml` file and `dep_graph_visualizer:` pubspec key are still read, with a deprecation warning.

### Layer presets

Instead of listing layers yourself, pick a preset:

```yaml
# arch_guard.yaml
preset: clean_architecture
```

| Preset | Layers | Main rules |
| :--- | :--- | :--- |
| `clean_architecture` | `core`, `domain`, `data`, `presentation` | `domain` imports only `core`; `presentation` may not import `data`. |
| `riverpod` | `domain`, `data`, `application`, `presentation` | `domain` imports nothing else; `data` never imports `application` or `presentation`. |
| `bloc` | `models`, `business_logic`, `repository`, `data_provider`, `presentation` | UI → bloc/cubit → repository → data provider; `models` everywhere. |
| `feature_first` | `shared` + one `feature_<name>` per folder in `lib/features` (or `lib/modules`) | A feature imports only itself and `shared` (`lib/core`, `lib/shared`, `lib/common`). |

Patterns use `**/<layer>/**`, so `lib/domain/...` and `lib/features/auth/domain/...` both match. A file belongs to the first layer whose pattern matches it. `arch_guard init` writes the expanded layers as comments in the config, so you can see exactly what a preset checks.

To adjust a preset, list the layer under `layers:` with only the keys you want to change. New layer names are added:

```yaml
preset: clean_architecture
layers:
  presentation:
    allowed_imports: [core, domain, presentation, data]   # allow UI -> data
  di:
    patterns: ["lib/di/**"]
    allowed_imports: [core, domain, data, presentation, di]
```

### `arch_guard init`

```bash
arch_guard init                      # detect the layout and write arch_guard.yaml
arch_guard init --preset bloc        # choose a preset (auto | none | clean_architecture | feature_first | bloc | riverpod)
arch_guard init --dry-run            # print the config instead of writing it
arch_guard init --force              # overwrite an existing arch_guard.yaml
```

After writing the file, `init` scans the project and prints how many files fall into each layer, how many violations and cycles exist, and what to do next (usually `--update-baseline` on an existing codebase).

### Reading a layer violation

```text
❌ Layer Violation: [presentation] lib/features/auth/presentation/page.dart:3 -> [data] lib/features/auth/data/repo.dart
   Rule: `presentation` may only import `core`, `domain`, `presentation`.
```

To fix it, either invert the dependency (put an interface in a layer the importing file may use, and implement it in the other layer), move the code to a layer it may import, or, if the dependency is intended, add the layer to `allowed_imports`.

### Workspaces & monorepos

With `--workspace` (the default), member packages come from the root `pubspec.yaml` `workspace:` list. If there is no such list, packages under `packages/` and `apps/` are auto-discovered (ignoring `example/`, `test/` and `tool/` folders). A plain single-package project is scanned using `--scan-dir`.

### Adopting on an existing codebase (baseline)

Large projects rarely start clean. Record the problems you have today, commit the file, and from then on only *new* problems fail the run:

```bash
arch_guard --update-baseline        # writes arch_guard_baseline.json
git add arch_guard_baseline.json
```

How later runs compare against the baseline:

- A **layer violation** is known if the same `source -> target` import is listed.
- A **cycle** is known if all its files belong to one baseline cycle. A cycle that shrinks stays accepted; one that grows, or merges two known cycles, is new.
- When baseline entries disappear, the run says so. Run `--update-baseline` again to lock in the improvement so the problems cannot come back.

Use `--baseline path/to/file.json` to keep the file somewhere else (paths are relative to the scanned project).

---

## Command Reference

### Basic Syntax

```bash
arch_guard [project_path] [options]
arch_guard init [project_path] [--preset <name>] [--dry-run] [--force]
```

If `[project_path]` is omitted, it defaults to current directory (`.`). See [`arch_guard init`](#arch_guard-init) for the init options.

---

### Command Options & Flags

| Flag / Option | Short | Description | Default |
| :--- | :--- | :--- | :--- |
| `--format` | `-f` | Output format(s): `text`, `dot`, `html`, `json`, `mermaid`, `sarif`, `markdown`, `all`. Repeatable. | `text` |
| `--scope` | | Export scope: `cycles` (SCCs + 1-hop context) or `all` (full graph). | `cycles` |
| `--explain` | | Inspect incoming/outgoing dependencies and SCC membership for a target file. | |
| `--output` | `-o` | Output directory path for generated files. | `arch_guard_output` |
| `--scan-dir` | | Subdirectory/subdirectories within project root to scan. Repeatable. | `lib` |
| `--exclude` | | Custom glob pattern(s) to exclude from scanning. Repeatable. | Default excludes (`*.g.dart`, etc.) |
| `--offline` | | Inline static assets in HTML report for air-gapped CI environments. | `false` |
| `--color` / `--no-color` | | Enable or disable ANSI color styling in terminal output. | `--color` (enabled) |
| `--fail-on-cycle` / `--no-fail-on-cycle` | | Return exit code `1` if circular dependencies are found. | `--fail-on-cycle` (enabled) |
| `--workspace` / `--no-workspace` | | Auto-discover member packages in Dart 3.6+ workspace or monorepo. | `--workspace` (enabled) |
| `--baseline` | | Baseline file of known problems. When it exists, only new problems fail the run. | `arch_guard_baseline.json` |
| `--update-baseline` | | Write current cycles and layer violations to the baseline and exit `0`. | |
| `--version` | | Print the arch_guard version. | |
| `--help` | `-h` | Display usage help and available CLI flags. | |

---

### CLI Command Recipes

#### 1. Basic Terminal Scan (Current Directory)
Scans current project and outputs colored summary with SCC severity metrics:
```bash
arch_guard
```

#### 2. Explain Target File Dependencies
Inspect why a specific file belongs to an SCC and view its direct incoming/outgoing edges:
```bash
arch_guard . --explain lib/services/auth_service.dart
```

#### 3. Export Native Mermaid.js Diagram for GitHub PRs
Generates a `.mmd` diagram ready to paste into GitHub/GitLab PRs or READMEs:
```bash
arch_guard . -f mermaid -o build/reports
```

#### 4. Export Machine-Readable JSON for CI Pipelines
Generates JSON report containing nodes, edges, SCC metrics, and layer violations:
```bash
arch_guard . -f json -o build/reports
```

#### 5. Generate Scalable Interactive Centerpiece HTML Visualizer
Exports interactive HTML graph with physics stabilization and `--scope cycles` scalability:
```bash
arch_guard . -f html -o build/reports
```

#### 6. Export All Formats (Text + DOT + HTML + JSON + Mermaid)
```bash
arch_guard . -f all -o build/reports
```

#### 7. Air-Gapped / Offline CI Execution
```bash
arch_guard . -f html --offline -o build/reports
```

#### 8. SARIF for Code Scanning and Markdown for PR Comments
```bash
arch_guard . -f sarif -f markdown -o build/reports
```

---

### Exit Codes

| Exit Code | Description |
| :---: | :--- |
| `0` | **Success**: Scan completed with zero circular dependencies or layer violations. |
| `1` | **Violations / Cycles Found**: Circular dependencies or Clean Architecture layer violations detected (only new ones when a baseline exists). |
| `2` | **Scan Error**: Provided directory does not exist, the project could not be scanned, or the baseline file is invalid. |
| `64` | **Usage Error**: Invalid CLI flags or arguments provided (`EX_USAGE`). |

---

## CI & Git Hook Integration

### GitHub Action

```yaml
# .github/workflows/architecture.yml
name: Architecture
on: [pull_request]

permissions:
  contents: read
  pull-requests: write     # PR comment
  # security-events: write # only with upload-sarif: true

jobs:
  arch_guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: creatorpiyush/arch_guard@v1.4.0
        with:
          path: .                  # project to scan
          args: --scan-dir lib     # any extra CLI flags
          # upload-sarif: true     # show results in the Security tab / PR diff
```

The action downloads the release binary (checksum-verified, no Dart SDK needed), writes the Markdown summary to the job summary, keeps a single PR comment up to date, and fails the job when arch_guard exits non-zero. Inputs: `path`, `version`, `args`, `comment`, `upload-sarif`, `output-dir`, `token`. Outputs: `exit-code`, `sarif-file`, `markdown-file`. Prebuilt binaries cover Linux x64/arm64, macOS arm64 and Windows x64; on other runners install Dart and set `version: source`.

Code Scanning (`upload-sarif: true`) is free for public repositories; private repositories need GitHub Advanced Security.

### GitLab CI

```yaml
arch_guard:
  image: dart:stable
  script:
    - dart pub global activate arch_guard
    - dart pub global run arch_guard . -f sarif -f markdown -o reports
  artifacts:
    when: always
    paths: [reports/]
```

GitLab does not read SARIF natively, so keep the reports as artifacts; `reports/arch_guard_report.md` can be posted to the merge request from a script.

### pre-commit

With [pre-commit](https://pre-commit.com) 2.15 or later:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/creatorpiyush/arch_guard
    rev: v1.4.0
    hooks:
      - id: arch_guard
        # args: [--no-fail-on-cycle]
```

### lefthook

```yaml
# lefthook.yml
pre-commit:
  commands:
    arch_guard:
      glob: "*.dart"
      run: dart run arch_guard --no-color
```

(Requires `arch_guard` as a dev dependency.)

### Plain git hook

Save as `.git/hooks/pre-commit` and make it executable (`chmod +x .git/hooks/pre-commit`):

```bash
#!/bin/sh
dart run arch_guard --no-color || {
  echo "arch_guard found new architecture problems; commit aborted."
  exit 1
}
```

With a committed baseline, hooks only block commits that introduce *new* problems.

---

## Programmatic Usage

```dart
import 'package:arch_guard/arch_guard.dart';

void main() async {
  // 1. Parallel scan of project or workspace
  final scanner = ProjectScanner(
    rootPath: '.',
    scanDirs: ['lib'],
    exclude: ['*.g.dart', '*.freezed.dart'],
    enableWorkspace: true,
  );

  final result = await scanner.scan();
  print('Scanned ${result.files.length} files across ${result.workspacePackageCount} packages.');

  // 2. Compute graph and find Tarjan SCC components
  final graph = DependencyGraph.fromScanResult(result);
  final cycles = graph.findCircularDependencies();

  for (final cycle in cycles) {
    final scc = cycle.scc;
    if (scc != null) {
      print('SCC #${scc.id}: ${scc.files.length} files | Hub: ${scc.hubFile}');
    }
  }

  // 3. Validate Clean Architecture layers
  const config = ArchGuardConfig(
    layers: {
      'domain': LayerDefinition(name: 'domain', patterns: ['lib/domain/**'], allowedImports: ['domain']),
      'presentation': LayerDefinition(name: 'presentation', patterns: ['lib/presentation/**'], allowedImports: ['presentation', 'domain']),
    },
  );

  final violations = LayerValidator.validate(result: result, config: config);
  print('Layer violations: ${violations.length}');

  // 4. Export JSON & Mermaid
  final jsonReport = JsonExporter.export(result: result, cycles: cycles);
  final mermaid = MermaidExporter.export(result: result, cycles: cycles);
}
```

---

## Development & CI/CD Workflows

### 1. Pre-Commit Check
Run pre-commit checks to verify code formatting, static analysis (`dart analyze --fatal-infos`), and unit tests:

```bash
./tool/pre_commit.sh
```

---

### 2. Pre-Release Verification
Before publishing a new version to **pub.dev**, run the pre-release script to ensure working directory cleanliness, `pubspec.yaml` vs `CHANGELOG.md` version sync, static analysis, unit tests, and pub package dry-run validation:

```bash
./tool/pre_release.sh
```

## License

[MIT License](LICENSE) — See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party software attributions.
