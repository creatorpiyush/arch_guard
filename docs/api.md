---
title: Dart API
---

[Home](index.md) · [Presets](presets.md) · [Configuration](configuration.md) · [CI & hooks](ci.md) · [CLI](cli.md) · [Dart API](api.md)

# Dart API

Everything the CLI does is available from `package:arch_guard/arch_guard.dart`, for custom reports, lint dashboards or IDE tooling. The full reference is on [pub.dev](https://pub.dev/documentation/arch_guard/latest/).

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

## Main classes

| Class | Purpose |
| :--- | :--- |
| `ProjectScanner` | Finds Dart files (and workspace packages) and reads their directives into a `ScanResult`. |
| `DependencyGraph` | Builds the graph and finds strongly connected components (`findCircularDependencies`). |
| `ArchGuardConfig` | Loads `arch_guard.yaml` / `pubspec.yaml`, including presets. |
| `LayerValidator` | Checks edges against layers (`validate`) and reports layer coverage (`coverage`). |
| `Baseline` | Reads, writes and compares against `arch_guard_baseline.json`. |
| `LayoutDetector` | Guesses a preset from the folder layout, as `init` does. |
| `DependencyExplainer` | Explains one file's imports, importers and cycle membership. |
| `TextReporter`, `HtmlExporter`, `MermaidExporter`, `DotExporter`, `JsonExporter`, `SarifExporter`, `MarkdownExporter` | Render the results. |
