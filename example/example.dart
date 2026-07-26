import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';

void main() async {
  print('=== Single Package Scan ===');
  await scanSinglePackage();

  print('\n=== Monorepo Workspace Scan ===');
  await scanWorkspaceMonorepo();
}

Future<void> scanSinglePackage() async {
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

  print('Found ${cycles.length} circular dependency groups:');
  for (final cycle in cycles) {
    print('  Cycle chain: ${cycle.exampleChain.join(" -> ")}');
  }
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
