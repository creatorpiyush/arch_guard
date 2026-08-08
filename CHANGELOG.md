# 1.1.3

- **Fix: Layer validator now works correctly in workspace/monorepo mode** (`LayerValidator`): Layer glob patterns such as `lib/domain/**` were silently never matching workspace-prefixed file paths (e.g. `packages/auth_pkg/lib/domain/entity.dart`). The validator now also tests the `lib/…` suffix of each path, making single-package and workspace `arch_guard.yaml` configs interchangeable with no user-side changes required.
- **Fix: Cross-package edge resolution path separator on Windows** (`ImportReader.resolveUri`): `p.normalize(p.join(…))` could produce backslash-separated paths on Windows, causing all resolved edge targets to silently miss the forward-slash-keyed `filesMap` and disappear from the graph. All three return paths now force `/` separators.
- **Fix: Missing space in workspace summary line** (`TextReporter`): The `Workspace Pkgs:` line was missing a space before the count, producing misaligned output (e.g. `Workspace Pkgs:3` instead of `Workspace Pkgs: 3`).

# 1.1.2

- **True `--offline` HTML Support**: Inlined Base64-encoded `vis-network.min.js` (v10.1.0 UMD) asset and system font fallbacks when `--offline` flag is specified.
- **Physics Stabilization Freeze**: Added `stabilizationIterationsDone` event listener to freeze Vis-Network force calculation after stabilization to eliminate CPU background spin.
- **Mermaid Exporter Disambiguation**: Added shared ID map with numeric suffix disambiguation for colliding file paths (e.g. `a-b.dart` vs `a_b.dart`) and quote label sanitization (`#quot;`).
- **Attribution & Notices**: Added `THIRD_PARTY_NOTICES.md` for bundled `vis-network` Apache-2.0/MIT software licensing.

# 1.1.1

- Refined `dep_graph.yaml` configuration examples and updated example application layout.
- Cleaned up maintainer CI documentation in `README.md`.

# 1.1.0

- **Strongly Connected Component (SCC) Severity Metrics**: Calculate internal edges, average fan-in, average fan-out, instability metric ($I$), graph coupling density ($D$), and bottleneck dependency hub files (`SccComponent`).
- **Clean Architecture & Layer Boundary Checker**: Configurable layer rules in `dep_graph.yaml` or `pubspec.yaml` with glob pattern matching (`LayerValidator`).
- **Targeted File Dependency Explainer**: Detailed file-level dependency path and cycle analysis via `--explain <file>`.
- **New Export Formats**: Machine-readable JSON report (`JsonExporter`) and GitHub/GitLab markdown flowchart diagram export (`MermaidExporter`).
- **High-Throughput Parallel Scanning**: Bounded parallel file reader queue (batch size 64) in `ProjectScanner`.
- **Scope & Offline Control**: Added `--scope cycles|all` graph scope trimming and `--offline` HTML asset inlining.

# 1.0.1

- Updated License to MIT

# 1.0.0

- Initial release of `dep_graph_visualizer`.
- Monorepo & Dart 3.6+ Workspace auto-discovery (`pubspec.yaml` `workspace:` entries and Melos sub-package structures).
- Cross-package import resolution (`package:<member_pkg>/...`) and inter-package circular dependency detection.
- Project scanner with regex directive parser.
- Circular dependency detector using Tarjan's SCC algorithm.
- Terminal text reporter with ANSI colors.
- Graphviz `.dot` exporter.
- Interactive single-file centerpiece HTML graph visualizer.
- Full CLI supporting repeatable `-f`, `-o`, `--scan-dir`, `--exclude`, and `--[no-]workspace` flags.
- Added conditional import/export support by treating every quoted URI in a directive as a potential dependency edge.
- Added a Flutter-style fixture and tests covering circular dependency detection through conditional imports.
