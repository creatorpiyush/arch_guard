import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyExplainer', () {
    test('explains target file dependencies and SCC membership', () {
      final mockResult = const ScanResult(
        packageName: 'explainer_pkg',
        files: {
          'lib/service.dart': FileNode(
            relativePath: 'lib/service.dart',
            absolutePath: '/abs/lib/service.dart',
          ),
          'lib/model.dart': FileNode(
            relativePath: 'lib/model.dart',
            absolutePath: '/abs/lib/model.dart',
          ),
        },
        edges: [
          GraphEdge(from: 'lib/service.dart', to: 'lib/model.dart'),
          GraphEdge(from: 'lib/model.dart', to: 'lib/service.dart'),
        ],
      );

      final graph = DependencyGraph.fromScanResult(mockResult);
      final cycles = graph.findCircularDependencies();

      final explanation = DependencyExplainer.explainFile(
        targetFile: 'lib/service.dart',
        graph: graph,
        cycles: cycles,
        color: false,
      );

      expect(
        explanation,
        contains('Dependency Explanation for: lib/service.dart'),
      );
      expect(explanation, contains('Strongly Connected Component #1'));
      expect(explanation, contains('Incoming Dependencies'));
      expect(explanation, contains('Outgoing Dependencies'));
    });
  });
}
