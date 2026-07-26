import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectScanner', () {
    test('scans sample_project fixture correctly', () async {
      final scanner = ProjectScanner(
        rootPath: 'example/sample_project',
        scanDirs: ['lib'],
      );

      final result = await scanner.scan();
      expect(result.packageName, equals('sample_project'));
      expect(result.files.length, greaterThanOrEqualTo(5));

      final graph = DependencyGraph.fromScanResult(result);
      final cycles = graph.findCircularDependencies();

      expect(cycles.length, equals(2));
    });

    test('detects a cycle in a Flutter-style conditional import fixture',
        () async {
      final scanner = ProjectScanner(
        rootPath: 'test/fixtures/flutter_conditional_app',
        scanDirs: ['lib'],
      );

      final result = await scanner.scan();
      expect(result.packageName, equals('flutter_conditional_app'));
      expect(result.files.length, equals(3));

      final graph = DependencyGraph.fromScanResult(result);
      final cycles = graph.findCircularDependencies();

      expect(cycles.length, equals(1));
      expect(cycles.first.files, contains('lib/main.dart'));
      expect(cycles.first.files, contains('lib/src/platform_stub.dart'));
    });
  });
}
