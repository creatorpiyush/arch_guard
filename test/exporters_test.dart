import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';
import 'package:test/test.dart';

void main() {
  group('Exporters', () {
    late ScanResult mockResult;
    late List<Cycle> mockCycles;

    setUp(() {
      mockResult = const ScanResult(
        packageName: 'demo_pkg',
        files: {
          'lib/a.dart': FileNode(
            relativePath: 'lib/a.dart',
            absolutePath: '/abs/a.dart',
          ),
          'lib/b.dart': FileNode(
            relativePath: 'lib/b.dart',
            absolutePath: '/abs/b.dart',
          ),
        },
        edges: [
          GraphEdge(from: 'lib/a.dart', to: 'lib/b.dart'),
          GraphEdge(from: 'lib/b.dart', to: 'lib/a.dart'),
        ],
      );

      mockCycles = [
        const Cycle(
          files: ['lib/a.dart', 'lib/b.dart'],
          exampleChain: ['lib/a.dart', 'lib/b.dart', 'lib/a.dart'],
        ),
      ];
    });

    test('TextReporter formats colored summary output', () {
      final reporter = const TextReporter(useColor: false);
      final text = reporter.formatReport(
        result: mockResult,
        cycles: mockCycles,
      );

      expect(text, contains('Dependency Graph Visualizer - Scan Summary'));
      expect(text, contains('Package Name:  demo_pkg'));
      expect(text, contains('Cycles Found:  1'));
      expect(text, contains('lib/a.dart'));
      expect(text, contains('-> lib/b.dart'));
    });

    test('DotExporter produces valid Graphviz syntax', () {
      final dot = DotExporter.export(result: mockResult, cycles: mockCycles);

      expect(dot, contains('digraph "Dependency Graph"'));
      expect(dot, contains('subgraph cluster_1'));
      expect(dot, contains('"lib/a.dart" -> "lib/b.dart"'));
    });

    test(
      'HtmlExporter produces valid centerpiece interactive HTML visualizer',
      () {
        final html = HtmlExporter.export(
          result: mockResult,
          cycles: mockCycles,
        );

        expect(html, contains('<!DOCTYPE html>'));
        expect(html, contains('vis-network'));
        expect(html, contains('demo_pkg'));
        expect(html, contains('id="graph-data"'));
        expect(html, contains('lib/a.dart'));
      },
    );
  });
}
