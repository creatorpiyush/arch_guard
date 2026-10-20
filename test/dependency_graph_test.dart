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

  group('DependencyGraph – conditional imports', () {
    List<Cycle> cycles(Map<String, String> sources) =>
        DependencyGraph.fromScanResult(
          ProjectScanner.scanSources(packageName: 'app', sources: sources),
        ).findCircularDependencies();

    test('a cycle only through a conditional import is platform-specific', () {
      final c = cycles({
        'lib/a.dart': "import 'stub.dart' if (dart.library.io) 'b.dart';\n",
        'lib/b.dart': "import 'a.dart';\n",
        'lib/stub.dart': '',
      }).single;
      expect(c.platformConditions, ['dart.library.io']);
      expect(c.platformNote, contains('if (dart.library.io)'));
      expect(c.toJson()['platformConditions'], ['dart.library.io']);
    });

    test('a cycle that plain imports also form is not', () {
      final c = cycles({
        'lib/a.dart':
            "import 'b.dart';\nimport 'stub.dart' if (dart.library.io) 'b.dart';\n",
        'lib/b.dart': "import 'a.dart';\n",
        'lib/stub.dart': '',
      }).single;
      expect(c.isPlatformSpecific, isFalse);
      expect(c.platformNote, isEmpty);
    });
  });
}
