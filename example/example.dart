import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';

void main() async {
  print('=== 1. Single Package Scan with Tarjan SCC Metrics ===');
  await scanSinglePackageWithMetrics();

  print('\n=== 2. Clean Architecture Layer Boundary Check (using dep_graph.yaml) ===');
  await validateCleanArchitectureLayers();

  print('\n=== 3. Dependency Path Explainer ===');
  await explainTargetFile();

  print('\n=== 4. Monorepo Workspace Auto-Discovery Scan ===');
  await scanWorkspaceMonorepo();
}

Future<void> scanSinglePackageWithMetrics() async {
  final scanner = ProjectScanner(
    rootPath: 'example/sample_project',
    scanDirs: ['lib'],
  );

  final result = await scanner.scan();
  print(
    'Scanned ${result.files.length} files with ${result.edges.length} import edges.',
  );

  final graph = DependencyGraph.fromScanResult(result);
  final cycles = graph.findCircularDependencies();

  print('Found ${cycles.length} Strongly Connected Components (SCCs):');
  for (final cycle in cycles) {
    final scc = cycle.scc;
    if (scc != null) {
      print(
        '  • SCC #${scc.id}: ${scc.files.length} files, ${scc.internalEdgesCount} internal edges, Hub: ${scc.hubFile}',
      );
    }
    print('    Cycle path: ${cycle.exampleChain.join(" -> ")}');
  }

  // Export JSON report
  final jsonReport = JsonExporter.export(result: result, cycles: cycles);
  print('  Generated JSON Report (${jsonReport.length} bytes)');

  // Export Mermaid diagram
  final mermaidDiagram = MermaidExporter.export(
    result: result,
    cycles: cycles,
    scope: 'cycles',
  );
  print('  Generated Mermaid Diagram (${mermaidDiagram.length} bytes)');
}

Future<void> validateCleanArchitectureLayers() async {
  // Load configuration directly from example/sample_project/dep_graph.yaml
  final config = DepGraphConfig.load('example/sample_project');

  final scanner = ProjectScanner(
    rootPath: 'example/sample_project',
    scanDirs: ['lib'],
  );

  final result = await scanner.scan();
  final violations = LayerValidator.validate(result: result, config: config);

  print(
    'Loaded dep_graph.yaml (${config.layers.length} layers defined). Detected ${violations.length} layer violations.',
  );
  for (final v in violations) {
    print('  $v');
  }
}

Future<void> explainTargetFile() async {
  final scanner = ProjectScanner(
    rootPath: 'example/sample_project',
    scanDirs: ['lib'],
  );

  final result = await scanner.scan();
  final graph = DependencyGraph.fromScanResult(result);
  final cycles = graph.findCircularDependencies();

  final explanation = DependencyExplainer.explainFile(
    targetFile: 'lib/services/auth_service.dart',
    graph: graph,
    cycles: cycles,
    color: false,
  );

  print(explanation);
}

Future<void> scanWorkspaceMonorepo() async {
  final scanner = ProjectScanner(
    rootPath: 'example/sample_workspace',
    enableWorkspace: true,
  );

  final result = await scanner.scan();
  print(
    'Discovered ${result.workspacePackageCount} workspace packages, ${result.files.length} total files.',
  );

  final graph = DependencyGraph.fromScanResult(result);
  final cycles = graph.findCircularDependencies();

  print('Found ${cycles.length} cross-package circular dependency groups:');
  for (final cycle in cycles) {
    print('  Cross-package chain: ${cycle.exampleChain.join(" -> ")}');
  }
}
