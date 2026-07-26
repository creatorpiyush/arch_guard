import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';
import 'package:test/test.dart';

void main() {
  group('Workspace & Monorepo Scanning', () {
    test('discovers member packages in workspace_monorepo fixture', () {
      final pkgs = PubspecReader.discoverWorkspacePackages(
        'test/fixtures/workspace_monorepo',
      );

      expect(pkgs.containsKey('auth_pkg'), isTrue);
      expect(pkgs.containsKey('user_pkg'), isTrue);
      expect(pkgs['auth_pkg']!.libPath, equals('packages/auth_pkg/lib'));
      expect(pkgs['user_pkg']!.libPath, equals('packages/user_pkg/lib'));
    });

    test(
      'detects cross-package circular dependency across monorepo packages',
      () async {
        final scanner = ProjectScanner(
          rootPath: 'test/fixtures/workspace_monorepo',
          enableWorkspace: true,
        );

        final result = await scanner.scan();
        expect(result.isWorkspace, isTrue);
        expect(result.workspacePackageCount, equals(2));
        expect(result.files.length, equals(2));

        final graph = DependencyGraph.fromScanResult(result);
        final cycles = graph.findCircularDependencies();

        expect(cycles.length, equals(1));
        final cycleFiles = cycles.first.files.toSet();
        expect(cycleFiles, contains('packages/auth_pkg/lib/auth_service.dart'));
        expect(cycleFiles, contains('packages/user_pkg/lib/user_model.dart'));
      },
    );

    test(
      'scans example/sample_workspace and finds cross-package cycle',
      () async {
        final scanner = ProjectScanner(
          rootPath: 'example/sample_workspace',
          enableWorkspace: true,
        );

        final result = await scanner.scan();
        expect(result.isWorkspace, isTrue);
        expect(result.workspacePackageCount, equals(2));

        final graph = DependencyGraph.fromScanResult(result);
        final cycles = graph.findCircularDependencies();

        expect(cycles.length, equals(1));
      },
    );
  });
}
