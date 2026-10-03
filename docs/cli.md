---
title: CLI
---

[Home](index.md) · [Presets](presets.md) · [Configuration](configuration.md) · [CI & hooks](ci.md) · [CLI](cli.md) · [Dart API](api.md)

# CLI

```bash
arch_guard [project_path] [options]
arch_guard init [project_path] [--preset <name>] [--dry-run] [--force]
```

`project_path` defaults to the current directory. Run with `dart run arch_guard` when it is a dev dependency, `dart pub global run arch_guard` after `dart pub global activate arch_guard`, or use a standalone binary. `init` is described on the [Presets](presets.md) page.

## Options

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

## Output formats

| Format | File | Use it for |
| :--- | :--- | :--- |
| `text` | terminal | Day-to-day checks; SCC metrics and violations with the broken rule. |
| `html` | `dependency_graph.html` | Exploring the graph: search, click a cycle to focus it, see each file's imports. Add `--offline` to inline all assets. |
| `mermaid` | `.mmd` | Diagrams in GitHub/GitLab Markdown. |
| `dot` | `.dot` | Graphviz (`dot -Tsvg`), clustered by package. |
| `json` | `.json` | Dashboards and custom scripts. |
| `sarif` | `.sarif` | GitHub Code Scanning and SARIF viewers; results point at the import line. |
| `markdown` | `arch_guard_report.md` | PR comments and CI job summaries. |

## Recipes

### Scan the current project
Scans current project and outputs colored summary with SCC severity metrics:
```bash
arch_guard
```

### Explain one file
Inspect why a specific file belongs to an SCC and view its direct incoming/outgoing edges:
```bash
arch_guard . --explain lib/services/auth_service.dart
```

### Mermaid diagram
Generates a `.mmd` diagram ready to paste into GitHub/GitLab PRs or READMEs:
```bash
arch_guard . -f mermaid -o build/reports
```

### JSON report
Generates JSON report containing nodes, edges, SCC metrics, and layer violations:
```bash
arch_guard . -f json -o build/reports
```

### Interactive HTML graph
Exports interactive HTML graph with physics stabilization and `--scope cycles` scalability:
```bash
arch_guard . -f html -o build/reports
```

### Every format at once
```bash
arch_guard . -f all -o build/reports
```

### Offline HTML (air-gapped CI)
```bash
arch_guard . -f html --offline -o build/reports
```

### SARIF and Markdown for CI
```bash
arch_guard . -f sarif -f markdown -o build/reports
```

---

## Exit codes

| Exit Code | Description |
| :---: | :--- |
| `0` | **Success**: Scan completed with zero circular dependencies or layer violations. |
| `1` | **Violations / Cycles Found**: Circular dependencies or Clean Architecture layer violations detected (only new ones when a baseline exists). |
| `2` | **Scan Error**: Provided directory does not exist, the project could not be scanned, or the baseline file is invalid. |
| `64` | **Usage Error**: Invalid CLI flags or arguments provided (`EX_USAGE`). |

## Standalone binaries (no Dart SDK needed)

Prebuilt executables for Linux (x64, arm64), macOS (Apple Silicon) and Windows (x64) are attached to every [GitHub Release](https://github.com/creatorpiyush/arch_guard/releases), along with a `SHA256SUMS.txt` file for checksum verification:

```bash
# Example: Linux x64 in CI
curl -fsSL -o arch_guard https://github.com/creatorpiyush/arch_guard/releases/latest/download/arch_guard-linux-x64
chmod +x arch_guard
./arch_guard . --format mermaid
```
