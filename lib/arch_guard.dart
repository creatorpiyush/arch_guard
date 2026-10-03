/// Static architecture analysis, Clean Architecture layer governance, metrics, and dependency graph visualizer for Dart and Flutter projects.
///
/// Most people use the `arch_guard` command line tool. This library exposes
/// the same building blocks for custom tooling:
///
/// ```dart
/// final result = await ProjectScanner(rootPath: '.').scan();
/// final cycles = DependencyGraph.fromScanResult(result)
///     .findCircularDependencies();
/// final violations = LayerValidator.validate(
///   result: result,
///   config: ArchGuardConfig.load('.'),
/// );
/// ```
///
/// See the [documentation](https://creatorpiyush.github.io/arch_guard/) for
/// configuration, presets and CI recipes.
library;

export 'src/baseline/baseline.dart';
export 'src/checker/layer_validator.dart';
export 'src/exporters/dot_exporter.dart';
export 'src/exporters/html_exporter.dart';
export 'src/exporters/json_exporter.dart';
export 'src/exporters/markdown_exporter.dart';
export 'src/exporters/mermaid_exporter.dart';
export 'src/exporters/sarif_exporter.dart';
export 'src/graph/dependency_explainer.dart';
export 'src/graph/dependency_graph.dart';
export 'src/models/config_model.dart';
export 'src/models/cycle.dart';
export 'src/models/file_node.dart';
export 'src/models/layer_presets.dart';
export 'src/models/scan_result.dart';
export 'src/models/scc_component.dart';
export 'src/models/workspace_package.dart';
export 'src/reporters/text_reporter.dart';
export 'src/scanner/project_scanner.dart';
export 'src/scanner/layout_detector.dart';
export 'src/scanner/pubspec_reader.dart';
export 'src/version.dart';
