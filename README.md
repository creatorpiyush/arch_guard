# dep_graph_visualizer

A pub.dev-ready CLI tool and Dart library to scan Dart/Flutter projects and monorepos, discover import & export dependencies, detect circular dependencies using **Tarjan's Strongly Connected Components (SCC) algorithm**, and export clean visual graph outputs (Terminal text, Graphviz `.dot`, and a rich interactive HTML visualizer centerpiece).

---

## Features

- 🚀 **Fast static scanning**: Lightweight regex directive parser that scans without building slow full AST trees.
- 🏢 **Monorepo & Dart Workspace Auto-Discovery**: Automatically discovers member packages in Dart 3.6+ workspaces (`workspace: [...]`) or Melos repositories (`packages/*`, `apps/*`), mapping cross-package imports and detecting inter-package cycles.
- ⚡ **Tarjan's SCC Cycle Detection**: Accurate, non-recursive cycle group identification handling multi-node loops, 2-file cycles, self-imports, and multi-package cycles.
- 🎨 **Interactive Centerpiece HTML Visualizer**:
  - Dark mode design powered by Vis-network.
  - Glowing red pulse effects on cyclic nodes.
  - Interactive sidebar highlighting cycle chains step-by-step.
  - Search/filter bar and node details inspector.
- 📄 **Graphviz DOT Exporter**: Grouped `subgraph cluster` format ready for `dot -Tsvg` rendering.
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
| `--format` | `-f` | Output format(s) to generate (`text`, `dot`, `html`, `all`). Can be passed multiple times. | `text` |
| `--output` | `-o` | Output directory path for generated `.dot` or `.html` files. | `dep_graph_output` |
| `--scan-dir` | | Subdirectory/subdirectories within project root to scan. Repeatable. | `lib` |
| `--exclude` | | Custom glob pattern(s) to exclude from scanning. Repeatable. | Default excludes (`*.g.dart`, etc.) |
| `--color` / `--no-color` | | Enable or disable ANSI color styling in terminal output. | `--color` (enabled) |
| `--fail-on-cycle` / `--no-fail-on-cycle` | | Return exit code `1` if circular dependencies are found (useful for CI/CD). | `--fail-on-cycle` (enabled) |
| `--workspace` / `--no-workspace` | | Auto-discover and scan member packages in a Dart 3.6+ workspace or monorepo. | `--workspace` (enabled) |
| `--help` | `-h` | Display usage help and available CLI flags. | |

---

### CLI Command Recipes

#### 1. Basic Terminal Scan (Current Directory)
Scans the current project and outputs a colored summary of circular dependencies to terminal:
```bash
dep_graph_visualizer
```

#### 2. Generate Interactive Centerpiece HTML Visualizer
Exports a single-file interactive HTML graph visualizer with glowing node pulses and path highlighting:
```bash
dep_graph_visualizer . -f html -o build/reports
```

#### 3. Export Graphviz `.dot` File
Generates a `.dot` file with clustered sub-graphs for cycle groups:
```bash
dep_graph_visualizer . -f dot -o build/reports
```
*(You can convert the `.dot` file to SVG using Graphviz: `dot -Tsvg build/reports/dependency_graph.dot -o graph.svg`)*

#### 4. Export All Formats (Terminal + DOT + HTML)
Generates both `.dot` and `.html` visualizer files while printing the text summary:
```bash
dep_graph_visualizer . -f all -o build/reports
```

#### 5. Monorepo & Dart 3.6+ Workspace Scan
Scan an entire monorepo root (e.g. Melos or Dart 3.6+ workspace). Auto-discovers member packages and maps cross-package cycles:
```bash
dep_graph_visualizer /path/to/my_monorepo -f all -o build/reports
```

#### 6. Scan Custom Directories (e.g., `lib` and `test`)
Scan multiple target subdirectories within a project:
```bash
dep_graph_visualizer . --scan-dir lib --scan-dir test
```

#### 7. Custom Exclude Globs
Exclude generated files or custom folders:
```bash
dep_graph_visualizer . --exclude "**/*.g.dart" --exclude "**/*.freezed.dart" --exclude "**/*.mocks.dart"
```

#### 8. Disable Single-Package Workspace Auto-Discovery
Force scanner to operate only on the specified directory without searching for child workspace packages:
```bash
dep_graph_visualizer . --no-workspace
```

#### 9. Non-Blocking CI/CD Mode (Always Exit 0)
Prints detected circular dependencies but returns exit code `0` even if cycles are found:
```bash
dep_graph_visualizer . --no-fail-on-cycle
```

#### 10. Plain Text Output (No ANSI Terminal Colors)
Useful for logging to file or CI pipeline logs:
```bash
dep_graph_visualizer . --no-color > scan_report.txt
```

---

### Exit Codes

| Exit Code | Description |
| :---: | :--- |
| `0` | **Success**: Scan completed with zero circular dependencies found (or `--no-fail-on-cycle` was specified). |
| `1` | **Circular Dependencies Found**: Cycles detected and `--fail-on-cycle` (default) is enabled. |
| `2` | **Scan Error**: Provided directory does not exist or target project could not be scanned. |
| `64` | **Usage Error**: Invalid CLI flags or arguments provided (`EX_USAGE`). |

---

## Programmatic Usage

You can also use `dep_graph_visualizer` directly in Dart/Flutter tools or custom build scripts:

```dart
import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';

void main() async {
  // 1. Scan project or workspace monorepo root
  final scanner = ProjectScanner(
    rootPath: '.',
    scanDirs: ['lib'],
    exclude: ['*.g.dart', '*.freezed.dart'],
    enableWorkspace: true,
  );

  final result = await scanner.scan();
  print('Scanned ${result.files.length} files across ${result.workspacePackageCount} packages.');

  // 2. Build graph and detect circular dependencies
  final graph = DependencyGraph.fromScanResult(result);
  final cycles = graph.findCircularDependencies();

  print('Found ${cycles.length} circular dependency groups:');
  for (final cycle in cycles) {
    print('  Cycle chain: ${cycle.exampleChain.join(" -> ")}');
  }

  // 3. Export HTML visualizer
  final html = HtmlExporter.export(result: result, cycles: cycles);
  print('Generated HTML graph visualizer (${html.length} bytes)');
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

---

### 3. GitHub Actions CI & Automated Publishing

This repository includes pre-configured GitHub Actions workflows:

- **PR & Commit Verification** (`.github/workflows/verify.yml`): Runs `dart format`, `dart analyze --fatal-infos`, `dart test`, and `dart pub publish --dry-run` on PRs and pushes to `main`/`master`.
- **Pub.dev Publishing** (`.github/workflows/publish.yml`): Publishes the package directly to [pub.dev](https://pub.dev) when a release is published or tag matching `v*` is pushed.

#### Setting up Pub.dev OIDC Publishing:
1. Go to [pub.dev](https://pub.dev) and log in as the package publisher/owner.
2. Navigate to package settings for `dep_graph_visualizer` and enable **Automated Publishing**.
3. Link your GitHub Repository (`<owner>/dep_graph_visualizer`) with automated publishing via OIDC.

---

## License

[MIT License](LICENSE)

