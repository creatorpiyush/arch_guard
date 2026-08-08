import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyGraph', () {
    test('detects cycles from scan result', () {
      const scanResult = ScanResult(
        packageName: 'test_pkg',
        files: {
          'lib/a.dart': FileNode(
            relativePath: 'lib/a.dart',
            absolutePath: '/abs/a.dart',
          ),
          'lib/b.dart': FileNode(
            relativePath: 'lib/b.dart',
            absolutePath: '/abs/b.dart',
          ),
          'lib/c.dart': FileNode(
            relativePath: 'lib/c.dart',
            absolutePath: '/abs/c.dart',
          ),
        },
        edges: [
          GraphEdge(from: 'lib/a.dart', to: 'lib/b.dart'),
          GraphEdge(from: 'lib/b.dart', to: 'lib/a.dart'),
          GraphEdge(from: 'lib/b.dart', to: 'lib/c.dart'),
        ],
      );

      final graph = DependencyGraph.fromScanResult(scanResult);
      final cycles = graph.findCircularDependencies();

      expect(cycles.length, equals(1));
      expect(cycles.first.files.toSet(), equals({'lib/a.dart', 'lib/b.dart'}));
      expect(
        cycles.first.exampleChain.first,
        equals(cycles.first.exampleChain.last),
      );
    });
  });
}
