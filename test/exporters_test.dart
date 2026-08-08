import 'package:arch_guard/arch_guard.dart';
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

      expect(text, contains('arch_guard - Scan Summary'));
      expect(text, contains('Package Name:  demo_pkg'));
      expect(text, contains('SCC Cycles:    1'));
      expect(text, contains('lib/a.dart'));
      expect(text, contains('-> lib/b.dart'));
    });

    test('DotExporter produces valid Graphviz syntax', () {
      final dot = DotExporter.export(result: mockResult, cycles: mockCycles);

      expect(dot, contains('digraph "Dependency Graph"'));
      expect(dot, contains('subgraph cluster_1'));
      expect(dot, contains('"lib/a.dart" -> "lib/b.dart"'));
    });

    test('JsonExporter produces valid JSON output', () {
      final json = JsonExporter.export(result: mockResult, cycles: mockCycles);

      expect(json, contains('"packageName": "demo_pkg"'));
      expect(json, contains('"sccCount": 1'));
      expect(json, contains('"lib/a.dart"'));
    });

    test('MermaidExporter produces valid markdown diagram syntax', () {
      final mermaid = MermaidExporter.export(
        result: mockResult,
        cycles: mockCycles,
      );

      expect(mermaid, contains('```mermaid'));
      expect(mermaid, contains('flowchart TD'));
      expect(mermaid, contains('lib_a_dart["lib/a.dart"]:::cyclicNode'));
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

    test('HtmlExporter without --offline references external CDN assets', () {
      final html = HtmlExporter.export(result: mockResult, cycles: mockCycles);
      expect(html, contains('https://unpkg.com/vis-network'));
      expect(html, contains('https://fonts.googleapis.com'));
    });

    test(
      'HtmlExporter with --offline makes no outbound network references',
      () {
        final html = HtmlExporter.export(
          result: mockResult,
          cycles: mockCycles,
          offline: true,
        );
        expect(html, isNot(contains('unpkg.com')));
        expect(html, isNot(contains('fonts.googleapis.com')));
        expect(html, contains('<script>'));
        expect(html.length, greaterThan(500000)); // bundled JS inlined
      },
    );

    test(
      'MermaidExporter disambiguates node IDs that sanitize to the same value',
      () {
        final collidingResult = const ScanResult(
          packageName: 'demo_pkg',
          files: {
            'lib/a-b.dart': FileNode(
              relativePath: 'lib/a-b.dart',
              absolutePath: '/abs/a-b.dart',
            ),
            'lib/a_b.dart': FileNode(
              relativePath: 'lib/a_b.dart',
              absolutePath: '/abs/a_b.dart',
            ),
          },
          edges: [
            GraphEdge(from: 'lib/a-b.dart', to: 'lib/a_b.dart'),
            GraphEdge(from: 'lib/a_b.dart', to: 'lib/a-b.dart'),
          ],
        );
        final collidingCycles = [
          const Cycle(
            files: ['lib/a-b.dart', 'lib/a_b.dart'],
            exampleChain: ['lib/a-b.dart', 'lib/a_b.dart', 'lib/a-b.dart'],
          ),
        ];

        final mermaid = MermaidExporter.export(
          result: collidingResult,
          cycles: collidingCycles,
        );

        expect(mermaid, contains('lib/a-b.dart'));
        expect(mermaid, contains('lib/a_b.dart'));
        final nodeDeclarationCount = RegExp(
          r'\["lib/a[-_]b\.dart"\]',
        ).allMatches(mermaid).length;
        expect(nodeDeclarationCount, equals(2));
      },
    );
  });
}
