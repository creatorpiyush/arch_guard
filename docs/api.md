---
title: Dart API
description: Use arch_guard from Dart code for custom reports, dashboards and tooling.
---

# Dart API

Everything the CLI does is available from `package:arch_guard/arch_guard.dart`, for custom reports, dashboards or editor tooling. The full reference is on [pub.dev](https://pub.dev/documentation/arch_guard/latest/). For checks inside `dart test`, use [`expectArchitecture()`](testing.md) instead.

## Run a full analysis

`ArchAnalysis.run()` does what the CLI does: reads `arch_guard.yaml`, scans, finds cycles, checks every rule and compares with the baseline. The CLI derives its exit code from the same result.

```dart
import 'package:arch_guard/arch_guard.dart';

Future<void> main() async {
  final analysis = await ArchAnalysis.run(
    projectPath: '.', // defaults shown
    scanDirs: ['lib'],
    useBaseline: true,
    // since: 'origin/main', // only problems in files changed on the branch
  );

  // What would make `arch_guard` exit 1, as readable lines.
  for (final problem in analysis.failures()) {
    print(problem);
  }

  // Or the typed results. The `new…` lists leave out what the baseline knows.
  print('Cycles: ${analysis.newCycles.length}');
  print('Layer violations: ${analysis.newLayerViolations.length}');
  print('Most coupled: ${analysis.hotspots.take(3).map((m) => m.file)}');
}
```

| Field | Contents |
| :--- | :--- |
| `scan`, `graph`, `config` | The `ScanResult`, `DependencyGraph` and loaded `ArchGuardConfig`. |
| `cycles`, `newCycles`, `oversizedCycles` | Circular dependency groups; the new ones; those over `max_scc_size`. |
| `layerViolations`, `packageViolations`, `workspaceViolations`, `metricViolations` | Rule failures. Each has a `new…` getter too. |
| `unusedFiles`, `newUnusedFiles` | Files no entry point reaches, when `unused_files:` is on. |
| `fileMetrics`, `hotspots` | Fan-in and fan-out per file; the most coupled first. |
| `coverage` | Which files fall into which layer, and which into none. |
| `baseline` | The comparison with the baseline file, or `null` without one. |
| `warnings` | Configuration warnings, as the CLI prints on stderr. |

## Build your own pipeline

Use the pieces directly when you don't want a config file or a baseline:

```dart
import 'package:arch_guard/arch_guard.dart';

Future<void> main() async {
  // 1. Scan the project (or workspace) into files and directives.
  final result = await ProjectScanner(
    rootPath: '.',
    scanDirs: ['lib'],
    exclude: ['*.g.dart', '*.freezed.dart'],
    enableWorkspace: true,
  ).scan();

  // 2. Build the graph and find cycles (Tarjan's strongly connected components).
  final graph = DependencyGraph.fromScanResult(result);
  final cycles = graph.findCircularDependencies();

  // 3. Check layers defined in code.
  const config = ArchGuardConfig(
    layers: {
      'domain': LayerDefinition(
        name: 'domain',
        patterns: ['lib/domain/**'],
        allowedImports: ['domain'],
      ),
      'presentation': LayerDefinition(
        name: 'presentation',
        patterns: ['lib/presentation/**'],
        allowedImports: ['presentation', 'domain'],
      ),
    },
  );
  final violations = LayerValidator.validate(result: result, config: config);

  // 4. Render any report.
  print(MermaidExporter.export(result: result, cycles: cycles));
  print('${cycles.length} cycles, ${violations.length} layer violations');
}
```

To read `arch_guard.yaml` instead of building the config in code, use `ArchGuardConfig.load('.')`.

## Classes

**Analysis**

| Class | Purpose |
| :--- | :--- |
| `ArchAnalysis` | A full run in one call. See [above](#run-a-full-analysis). |
| `expectArchitecture()` | In `package:arch_guard/testing.dart`. Runs `ArchAnalysis` and throws `ArchitectureViolationException` on failures. See [Tests](testing.md). |
| `ArchGuardConfig` | Loads `arch_guard.yaml` or the `pubspec.yaml` section (`load`), presets included. |
| `Baseline` | Reads, writes and compares against `arch_guard_baseline.json`. |
| `GitChanges` | Files changed since a git ref (`since`), as used by `--since`. |

**Scanning and the graph**

| Class | Purpose |
| :--- | :--- |
| `ProjectScanner` | Finds Dart files and workspace packages and reads their directives into a `ScanResult`. `scanSources()` scans in-memory content. |
| `DependencyGraph` | Builds the graph and finds cycles (`findCircularDependencies`). |
| `CycleBreaker` | Suggests the import to remove to break a cycle (`suggest`). The graph attaches it as `SccComponent.suggestedBreak`. |
| `DependencyExplainer` | One file's imports, importers and cycle membership, as `--explain` prints. |
| `ImportPath` | Shortest import chain between files, folders or packages (`find`), as `why` prints. |
| `AffectedFiles` | Files and tests reachable backwards from changed files (`find`), as `affected` prints. |
| `LayoutDetector` | Guesses a preset from the folder layout, as `init` does. |

**Rules**

| Class | Checks | Yields |
| :--- | :--- | :--- |
| `LayerValidator` | Imports against layers (`validate`); layer coverage (`coverage`). | `LayerViolation` |
| `PackageValidator` | `ScanResult.packageImports` against `forbidden_packages` (`validate`), or one import at a time (`checker`). | `PackageViolation` |
| `WorkspaceValidator` | Imports between workspace members against `workspace_rules`. | `WorkspaceViolation` |
| `MetricValidator` | `FileMetrics` against `metrics:` limits. | `MetricViolation` |
| `FileMetrics` | Fan-in, fan-out and instability per file (`compute`), most coupled first. | – |
| `UnusedFiles` | Files no entry point reaches (`find`). | – |

**Reports**

`TextReporter`, `HtmlExporter`, `MermaidExporter`, `DotExporter`, `JsonExporter`, `SarifExporter` and `MarkdownExporter` render the results in each [output format](cli.md#output-formats).
