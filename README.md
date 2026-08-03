# dep_graph_visualizer

A pub.dev-ready CLI tool and Dart library to scan Dart/Flutter projects and monorepos, discover import & export dependencies, detect circular dependencies using **Tarjan's Strongly Connected Components (SCC) algorithm**, enforce **Clean Architecture layer boundaries**, and export clean visual graph outputs (Terminal text, JSON, Mermaid `.mmd`, Graphviz `.dot`, and a rich interactive HTML centerpiece).

---

## Features

- 🚀 **High-Performance Concurrent Scanning**: Bounded parallel async scanner (`Future.wait` batching) designed for 1,000+ file codebases.
- 📐 **Clean Architecture Layer Validation**: Enforce directional rules (e.g. `domain` cannot import `presentation` or `data`) configured via `dep_graph.yaml` or `pubspec.yaml`.
- 📊 **Tarjan's SCC Severity Metrics**: Computes internal edge density, average Fan-In/Fan-Out, Instability ($I$), and dependency hub identification per SCC.
- 🔍 **CLI File Explainer (`--explain`)**: Interactively inspect incoming/outgoing dependencies and SCC membership for any specific file.
- 🏢 **Monorepo & Dart Workspace Auto-Discovery**: Automatically discovers member packages in Dart 3.6+ workspaces (`workspace: [...]`) or Melos repositories (`packages/*`, `apps/*`), mapping cross-package cycles.
- 🎨 **Multi-Format Exporters**:
  - **Interactive Centerpiece HTML**: Dark mode, Vis-network rendering with physics stabilization freeze, `--scope cycles` scalability, and `--offline` air-gapped support.
  - **Mermaid.js Diagram (`.mmd`)**: Native markdown diagrams ready for GitHub/GitLab PRs.
  - **JSON Data Report (`.json`)**: Machine-readable payload for CI/CD dashboards.
  - **Graphviz DOT (`.dot`)**: Subgraph-clustered DOT format for `dot -Tsvg`.
- 💻 **Pub.dev Ready & Flexible CLI**: Configurable flags, exit codes for CI/CD pipelines (`0`, `1`, `2`, `64`), and a clear programmatic Dart API.

---

## Installation

Add as a dependency in your `pubspec.yaml` or install globally via pub:

```bash
dart pub global activate dep_graph_visualizer
```

Or run directly using `dart run` in any project or monorepo directory:

```bash
dart run dep_graph_visualizer [path] [options]
```

---

## Configuration (`dep_graph.yaml` or `pubspec.yaml`)

Define Clean Architecture layer rules and ignore patterns in `dep_graph.yaml` at your project root:

```yaml
# dep_graph.yaml
ignore:
  - "**/*.g.dart"
  - "**/*.freezed.dart"
  - "**/*.mocks.dart"

fail_on_layer_violation: true

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

Or configure under `dep_graph_visualizer:` in `pubspec.yaml`.

---

## Command Reference

### Basic Syntax

```bash
dep_graph_visualizer [project_path] [options]
```

If `[project_path]` is omitted, it defaults to current directory (`.`).

---

### Command Options & Flags

| Flag / Option | Short | Description | Default |
| :--- | :--- | :--- | :--- |
| `--format` | `-f` | Output format(s): `text`, `dot`, `html`, `json`, `mermaid`, `all`. Repeatable. | `text` |
| `--scope` | | Export scope: `cycles` (SCCs + 1-hop context) or `all` (full graph). | `cycles` |
| `--explain` | | Inspect incoming/outgoing dependencies and SCC membership for a target file. | |
| `--output` | `-o` | Output directory path for generated files. | `dep_graph_output` |
| `--scan-dir` | | Subdirectory/subdirectories within project root to scan. Repeatable. | `lib` |
| `--exclude` | | Custom glob pattern(s) to exclude from scanning. Repeatable. | Default excludes (`*.g.dart`, etc.) |
| `--offline` | | Inline static assets in HTML report for air-gapped CI environments. | `false` |
| `--color` / `--no-color` | | Enable or disable ANSI color styling in terminal output. | `--color` (enabled) |
| `--fail-on-cycle` / `--no-fail-on-cycle` | | Return exit code `1` if circular dependencies are found. | `--fail-on-cycle` (enabled) |
| `--workspace` / `--no-workspace` | | Auto-discover member packages in Dart 3.6+ workspace or monorepo. | `--workspace` (enabled) |
| `--help` | `-h` | Display usage help and available CLI flags. | |

---

### CLI Command Recipes

#### 1. Basic Terminal Scan (Current Directory)
Scans current project and outputs colored summary with SCC severity metrics:
```bash
dep_graph_visualizer
```

#### 2. Explain Target File Dependencies
Inspect why a specific file belongs to an SCC and view its direct incoming/outgoing edges:
```bash
dep_graph_visualizer . --explain lib/services/auth_service.dart
```

#### 3. Export Native Mermaid.js Diagram for GitHub PRs
Generates a `.mmd` diagram ready to paste into GitHub/GitLab PRs or READMEs:
```bash
dep_graph_visualizer . -f mermaid -o build/reports
```

#### 4. Export Machine-Readable JSON for CI Pipelines
Generates JSON report containing nodes, edges, SCC metrics, and layer violations:
```bash
dep_graph_visualizer . -f json -o build/reports
```

#### 5. Generate Scalable Interactive Centerpiece HTML Visualizer
Exports interactive HTML graph with physics stabilization and `--scope cycles` scalability:
```bash
dep_graph_visualizer . -f html -o build/reports
```

#### 6. Export All Formats (Text + DOT + HTML + JSON + Mermaid)
```bash
dep_graph_visualizer . -f all -o build/reports
```

#### 7. Air-Gapped / Offline CI Execution
```bash
dep_graph_visualizer . -f html --offline -o build/reports
```

---

### Exit Codes

| Exit Code | Description |
| :---: | :--- |
| `0` | **Success**: Scan completed with zero circular dependencies or layer violations. |
| `1` | **Violations / Cycles Found**: Circular dependencies or Clean Architecture layer violations detected. |
| `2` | **Scan Error**: Provided directory does not exist or target project could not be scanned. |
| `64` | **Usage Error**: Invalid CLI flags or arguments provided (`EX_USAGE`). |

---

## Programmatic Usage

```dart
import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';

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
  const config = DepGraphConfig(
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

[MIT License](LICENSE)
