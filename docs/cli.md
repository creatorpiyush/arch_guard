---
title: CLI
description: Every arch_guard command, flag, output format and exit code.
---

# CLI

```bash
arch_guard [project_path] [options]          # check the project
arch_guard init [project_path] [options]     # write arch_guard.yaml
arch_guard affected --since <ref> [options]  # list tests a branch can affect
arch_guard why <from> <to> [project_path]    # show the import chain from A to B
```

`project_path` defaults to the current directory. How you call it depends on how you installed it:

| Installed with | Run as |
| :--- | :--- |
| `dart pub add --dev arch_guard` | `dart run arch_guard` |
| `dart pub global activate arch_guard` | `arch_guard` |
| [Standalone binary](#standalone-binaries) | `./arch_guard` |

## Commands

| Command | What it does | Exits `1` when |
| :--- | :--- | :--- |
| [`arch_guard`](#options) | Scans the project and checks every rule. | There are problems (only new ones, with a baseline). |
| [`init`](#init) | Detects your layout and writes `arch_guard.yaml`. | – |
| [`affected`](#tests-affected-by-a-branch) | Prints the test files changed code can reach. | – |
| [`why`](#why-does-a-depend-on-b) | Prints the shortest import chain between two files, folders or packages. | There is no such chain. |

## Options

Flags for the main check. Repeatable flags can be given more than once (`--scan-dir lib --scan-dir bin`).

**What to scan**

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--scan-dir` | `lib` | Folder to scan, relative to the project root. Repeatable. |
| `--exclude` | generated files | Glob of files to leave out, on top of `*.g.dart`, `*.freezed.dart` and other generated files. Repeatable. |
| `--[no-]workspace` | on | Find the members of a Dart workspace or Melos-style monorepo and scan them all. |

**What fails the run**

| Flag | Default | Description |
| :--- | :--- | :--- |
| `--[no-]fail-on-cycle` | on | Exit `1` when there are cycles. Other rules still fail the run when it is off. |
| `--baseline <file>` | `arch_guard_baseline.json` | Problems in this file are known and don't fail the run. |
| `--update-baseline` | | Write today's problems to the baseline and exit `0`. |
| `--since <ref>` | | Report only problems in files changed since the merge base with `<ref>`. See [below](#only-files-changed-on-this-branch). |

**Output**

| Flag | Default | Description |
| :--- | :--- | :--- |
| `-f`, `--format` | `text` | `text`, `html`, `mermaid`, `dot`, `json`, `sarif`, `markdown` or `all`. Repeatable. See [Output formats](#output-formats). |
| `-o`, `--output` | `arch_guard_output` | Folder for report files. |
| `--json` | off | Print the JSON report (the same as `-f json`) to stdout and nothing else, for scripts and AI agents. The usual report and warnings go to stderr. The exit code is unchanged. |
| `--scope` | `cycles` | What graphs show: `cycles` (each cycle plus the files one import away) or `all` (the full graph). |
| `--offline` | off | Inline the scripts in the HTML report, for machines without internet. |
| `--[no-]color` | on | ANSI colours in the terminal. |

**Other**

| Flag | Description |
| :--- | :--- |
| `--explain <file>` | Show one file's imports, importers and cycle membership. See [below](#explain-one-file). |
| `--watch` | Re-run on every change. See [Watch mode](#watch-mode). |
| `--version` | Print the version. |
| `-h`, `--help` | Print usage. |

These combinations are rejected with exit `64`: `--since` or `--watch` with `--update-baseline` or `--explain`, `--watch` with `init`, `affected` or `why`, and `--json` with `--watch` or `--explain`.

## Fix a cycle

Every cycle comes with the one import to remove to break it. When no single import does, it names the one that shrinks the cycle most.

```text
  Strongly Connected Component #1 (2 files)
    [Metrics: 2 internal edges | Avg Fan-In: 1.5 | Avg Fan-Out: 1.0 | Hub: lib/screens/home.dart]
    Representative Cycle Path:
    lib/widgets/nav.dart
    -> lib/screens/home.dart
    -> lib/widgets/nav.dart
    Suggested fix: remove lib/screens/home.dart:1 -> lib/widgets/nav.dart (breaks the cycle)
```

- **Fan-in / fan-out**: how many files import a file, and how many it imports. The **hub** is the most connected file inside the cycle, usually the place to start untangling.
- **Platform-specific cycles.** A cycle that exists only through a conditional import (`import 'stub.dart' if (dart.library.io) 'io.dart'`) is marked `Platform-specific (only through conditional imports: if (dart.library.io))`. It still counts, because it is real on that platform. In JSON, the conditions are under `platformConditions` and each conditional edge has a `condition` (`default` for the fallback URI).

## Only files changed on this branch

Analyse the whole project, but report and fail on only the problems that touch files changed since the merge base with `origin/main`, plus uncommitted and untracked files:

```bash
arch_guard --since origin/main
```

The report ends with `Only problems touching 7 file(s) changed since origin/main.`

- The whole project is still scanned, because a cycle needs the full graph.
- A `max_fan_in` violation counts when a changed file imports the over-limit file.
- In CI, check out with full history (`fetch-depth: 0`). See [CI](ci.md#large-repositories-only-changed-files).
- When git fails, for example on an unknown ref, the run exits `2`.

## Watch mode

Keep a terminal open while you refactor; the check re-runs on every save:

```bash
arch_guard --watch
arch_guard --watch --since origin/main     # only problems in changed files
```

- It re-runs when a scanned `.dart` file, `arch_guard.yaml`, a `pubspec.yaml` or the baseline changes.
- Changes are debounced by 300 ms, so one save is one run.
- `build/`, dot folders such as `.dart_tool` and report files are ignored, so `-f html` doesn't loop.
- After each run it prints `Watching <project> for changes (Ctrl+C to stop). Last run 14:02:11, exit 1.` A failing run keeps watching. Ctrl+C exits `0`.

## Explain one file

Why is this file in a cycle? What does it import, and what imports it?

```bash
arch_guard --explain lib/services/auth_service.dart
```

## Output formats

| Format | File | Use it for |
| :--- | :--- | :--- |
| `text` | terminal | Day-to-day checks: cycles with metrics, violations with the broken rule. |
| `html` | `dependency_graph.html` | Exploring the graph: search, click a cycle to focus it, see each file's imports. |
| `mermaid` | `.mmd` | Diagrams in GitHub or GitLab Markdown. |
| `dot` | `.dot` | Graphviz (`dot -Tsvg`), clustered by package. |
| `json` | `.json` | Dashboards and scripts: nodes, edges, cycles, violations, hotspots. |
| `sarif` | `.sarif` | GitHub Code Scanning and SARIF viewers. Results point at the import line. |
| `markdown` | `arch_guard_report.md` | PR comments and CI job summaries. |

```bash
arch_guard -f html -o build/reports              # interactive graph
arch_guard -f html --offline -o build/reports    # same, works without internet
arch_guard -f sarif -f markdown -o build/reports # for CI
arch_guard -f all -o build/reports               # everything
```

### Unused files in each format

With [`unused_files:`](configuration.md#unused-files) in the config:

| Format | What it shows |
| :--- | :--- |
| Terminal | Up to 20 files, then `… and N more`. With a baseline, only new ones. |
| JSON | The full sorted list under `unusedFiles`. The key is absent when the check is off. |
| SARIF | One result per file under the rule `unused-file`: `error` with `fail: true`, `warning` otherwise, with `baselineState` when a baseline is used. |
| Markdown | An *Unused files* row in the summary table, and a *New unused files* list. |

## init

```bash
arch_guard init                      # detect the layout and write arch_guard.yaml
arch_guard init --preset bloc        # auto | none | clean_architecture | feature_first | bloc | riverpod
arch_guard init --dry-run            # print the config instead of writing it
arch_guard init --force              # overwrite an existing arch_guard.yaml
```

After writing the file, `init` scans the project and prints how many files fall into each layer, how many problems exist, and what to do next. How it picks a preset is on the [Presets](presets.md) page.

## Tests affected by a branch

List the test files that changes since `origin/main` (plus uncommitted and untracked files) can affect, and run only those:

```bash
# single package (Flutter: flutter test)
t=$(arch_guard affected --since origin/main); [ -n "$t" ] && dart test $t

# melos monorepo: test only affected packages
p=$(arch_guard affected --since origin/main --print packages | paste -sd, -)
[ -n "$p" ] && melos exec --scope="$p" -- dart test
```

> **Keep the `[ -n ... ]` guard.** `dart test` with no paths runs every test.

| Option | Default | Description |
| :--- | :--- | :--- |
| `--since <ref>` | | Required. The git ref to compare with. |
| `--print` | `tests` | `tests`, `files` or `packages`, one per line on stdout. |
| `--json` | | Print `since`, `changedFiles`, `files`, `tests`, `packages` (`name`, `path`) and `ignoredChanges` as JSON. |
| `--exclude`, `--[no-]workspace` | | As for the main command. |

How it decides what is affected:

- It scans `lib/`, `test/` and `integration_test/` in the root and every workspace member.
- It follows imports, exports and `part` directives backwards from each changed file. Ignored and conditional imports count too, and `ignore:` in the config does not apply.
- A deleted or generated file (`*.g.dart`) affects the files that import it.
- A changed `pubspec.yaml` or `pubspec.lock` affects its whole package. The root one affects everything.

Notes go to stderr: changed non-Dart files that affect nothing, and `No affected tests.` when the list is empty.

## Why does A depend on B

Print the shortest import chain from a file or folder to a file, folder or package:

```bash
arch_guard why lib/domain flutter
```

```text
lib/domain/user.dart reaches package:flutter in 3 step(s):
  lib/domain/user.dart:3  import  lib/domain/repo.dart
  lib/domain/repo.dart:5  export  lib/data/api.dart
  lib/data/api.dart:1  import  package:flutter/material.dart
```

| Argument | Accepts |
| :--- | :--- |
| `<from>` | A file, a folder, or a file name that matches exactly one file (`user.dart`). |
| `<to>` | The same, plus `package:x`, a bare package name (`flutter`) or a core library (`dart:io`). |

- A conditional import step ends with `(if dart.library.io)`.
- With no chain, it prints `No import path from <from> to <to>.` and exits `1`, so a CI step can assert that a dependency never appears.
- An unknown argument, or a file name that matches several files, exits `64`.
- Accepts `--scan-dir`, `--exclude`, `--[no-]workspace` and `--[no-]color`.

See the [why example](https://github.com/creatorpiyush/arch_guard/tree/main/example/cases/why).

## Exit codes

| Code | Main check | `affected` | `why` |
| :---: | :--- | :--- | :--- |
| `0` | No problems (or none new, with a baseline). | Done, also when nothing is affected. | Found a chain. |
| `1` | Cycles, layer violations or other rule failures. | – | No chain. |
| `2` | Missing directory, unreadable project, invalid baseline, or git failed for `--since`. | Git failed. | The project could not be scanned. |
| `64` | Bad flags or arguments. | Bad flags, or no `--since`. | Bad arguments. |

## Standalone binaries

No Dart SDK needed. On Linux (x64, arm64), macOS (Apple Silicon) or Windows in Git Bash:

```bash
curl -fsSL https://creatorpiyush.github.io/arch_guard/install.sh | sh
```

The script downloads the binary for your platform from the latest [GitHub Release](https://github.com/creatorpiyush/arch_guard/releases), checks it against the release's `SHA256SUMS.txt` and installs it as `~/.local/bin/arch_guard`. Run it again to upgrade. Two environment variables change the defaults:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ARCH_GUARD_VERSION` | latest | Release to install, e.g. `1.15.0`. |
| `ARCH_GUARD_INSTALL_DIR` | `~/.local/bin` | Folder to install into. |

```bash
curl -fsSL https://creatorpiyush.github.io/arch_guard/install.sh | ARCH_GUARD_VERSION=1.15.0 sh
```

There is no binary for Intel macOS; use `dart pub global activate arch_guard` there. On Windows outside Git Bash, download `arch_guard-windows-x64.exe` from the release page by hand and compare it with `SHA256SUMS.txt`.
