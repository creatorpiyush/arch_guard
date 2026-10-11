import 'package:arch_guard/arch_guard.dart';

void main() async {
  print('=== 1. Single Package Scan with Tarjan SCC Metrics ===');
  await scanSinglePackageWithMetrics();

  print(
    '\n=== 2. Clean Architecture Layer Boundary Check (using arch_guard.yaml) ===',
  );
  await validateCleanArchitectureLayers();

  print('\n=== 3. Dependency Path Explainer ===');
  await explainTargetFile();

  print('\n=== 4. Monorepo Workspace Auto-Discovery Scan ===');
  await scanWorkspaceMonorepo();

  print('\n=== 5. Everything in One Call (what the CLI runs) ===');
  await runFullAnalysis();

  print('\n=== 6. Forbidden Packages and Metric Limits ===');
  await checkPackagesAndMetrics();

  print('\n=== 7. Workspace Rules ===');
  await checkWorkspaceRules();
}

Future<void> scanSinglePackageWithMetrics() async {
  final scanner = ProjectScanner(
    rootPath: 'example/cases/sample_project',
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
    // The one import whose removal breaks (or shrinks most) this cycle.
    final hint = scc?.suggestedBreak;
    if (hint != null) print('    Suggested fix: remove ${hint.describe()}');
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
  // Load configuration directly from example/cases/sample_project/arch_guard.yaml
  final config = ArchGuardConfig.load('example/cases/sample_project');

  final scanner = ProjectScanner(
    rootPath: 'example/cases/sample_project',
    scanDirs: ['lib'],
  );

  final result = await scanner.scan();
  final violations = LayerValidator.validate(result: result, config: config);

  print(
    'Loaded arch_guard.yaml (${config.layers.length} layers defined). Detected ${violations.length} layer violations.',
  );
  for (final v in violations) {
    print('  $v');
  }
}

Future<void> explainTargetFile() async {
  final scanner = ProjectScanner(
    rootPath: 'example/cases/sample_project',
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
    rootPath: 'example/cases/sample_workspace',
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

Future<void> runFullAnalysis() async {
  // Scan, cycles, layer/package/metric/workspace rules and the baseline in
  // one call. Pass `since: 'origin/main'` to keep only problems touching
  // files changed on the current branch (needs git).
  final analysis = await ArchAnalysis.run(
    projectPath: 'example/cases/sample_project',
  );

  print(
    '${analysis.cycles.length} cycles, '
    '${analysis.layerViolations.length} layer violations, '
    '${analysis.packageViolations.length} forbidden package imports.',
  );
  print('Most coupled files:');
  for (final m in analysis.hotspots.take(3)) {
    print('  ${m.file}: fan-in ${m.fanIn}, fan-out ${m.fanOut}');
  }

  // Exactly what would make `arch_guard` exit with 1.
  final failures = analysis.failures();
  print('${failures.length} problem(s) would fail the run:');
  for (final f in failures) {
    print('  - $f');
  }
}

Future<void> checkPackagesAndMetrics() async {
  // Usually this lives in arch_guard.yaml; parsed inline here so the sample
  // project's own config stays untouched.
  final config = ArchGuardConfig.parse('''
forbidden_packages:
  - "dart:mirrors"          # nowhere in the project
layers:
  models:
    patterns: ["lib/models/**"]
    allowed_imports: [models]
    forbidden_packages: ["dart:convert"]   # models stay plain data
metrics:
  max_fan_in: 1   # at most 1 project file may import a file
  max_fan_out: 1  # a file may import at most 1 project file
''', rootPath: 'example/cases/sample_project');

  final result = await ProjectScanner(
    rootPath: 'example/cases/sample_project',
  ).scan();

  for (final v in PackageValidator.validate(result: result, config: config)) {
    print('  $v');
    print('    ${v.rule}');
  }
  final metrics = MetricValidator.validate(
    metrics: FileMetrics.compute(result),
    config: config,
  );
  for (final v in metrics) {
    print('  $v');
  }
}

Future<void> checkWorkspaceRules() async {
  // user_package is the base package: it may not depend on other members.
  final config = ArchGuardConfig.parse('''
workspace_rules:
  "packages/user_package":
    allowed: []
  "packages/auth_package":
    allowed: ["packages/user_package"]
''', rootPath: 'example/cases/sample_workspace');

  final result = await ProjectScanner(
    rootPath: 'example/cases/sample_workspace',
    enableWorkspace: true,
  ).scan();

  for (final v in WorkspaceValidator.validate(result: result, config: config)) {
    print('  $v');
    print('    ${v.rule}');
  }
}
