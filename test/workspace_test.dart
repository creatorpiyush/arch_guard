import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates a minimal package (pubspec + one lib file) at [dir].
void _writePackage(String dir, String name, {String libSource = ''}) {
  Directory(p.join(dir, 'lib')).createSync(recursive: true);
  File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
  File(p.join(dir, 'lib', '$name.dart')).writeAsStringSync(libSource);
}

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

    test('single-package project is not treated as a workspace', () {
      final pkgs = PubspecReader.discoverWorkspacePackages(
        'example/sample_project',
      );
      expect(pkgs, isEmpty);
    });

    test('ignores example/ and test/ packages without a workspace list', () {
      // This repository has example/ and test/fixtures/ packages but no
      // `workspace:` key, so none of them are workspace members.
      final pkgs = PubspecReader.discoverWorkspacePackages('.');
      expect(pkgs, isEmpty);
    });

    group('auto-discovery without a workspace list', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('arch_guard_ws_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('discovers packages/ and apps/ members plus the root', () async {
        final root = tempDir.path;
        _writePackage(
          root,
          'root_app',
          libSource: "import 'package:core_pkg/core_pkg.dart';\n",
        );
        _writePackage(
          p.join(root, 'packages', 'core_pkg'),
          'core_pkg',
          libSource: "import 'package:root_app/root_app.dart';\n",
        );
        _writePackage(p.join(root, 'apps', 'mobile'), 'mobile');
        // Should be skipped: outside conventional locations / nested example.
        _writePackage(p.join(root, 'example'), 'root_example');
        _writePackage(
          p.join(root, 'packages', 'core_pkg', 'example'),
          'core_example',
        );

        final pkgs = PubspecReader.discoverWorkspacePackages(root);
        expect(pkgs.keys, unorderedEquals(['root_app', 'core_pkg', 'mobile']));
        expect(pkgs['root_app']!.packagePath, equals('.'));

        final result = await ProjectScanner(rootPath: root).scan();
        expect(result.workspacePackageCount, equals(3));
        expect(
          result.files.keys,
          unorderedEquals([
            'lib/root_app.dart',
            'packages/core_pkg/lib/core_pkg.dart',
            'apps/mobile/lib/mobile.dart',
          ]),
        );

        final cycles = DependencyGraph.fromScanResult(
          result,
        ).findCircularDependencies();
        expect(cycles.length, equals(1));
      });

      test('respects explicit workspace globs including example/', () {
        final root = tempDir.path;
        Directory(root).createSync(recursive: true);
        File(
          p.join(root, 'pubspec.yaml'),
        ).writeAsStringSync('name: ws_root\nworkspace:\n  - example\n');
        _writePackage(p.join(root, 'example'), 'ws_example');
        _writePackage(p.join(root, 'packages', 'unlisted'), 'unlisted');

        final pkgs = PubspecReader.discoverWorkspacePackages(root);
        expect(pkgs.keys, equals(['ws_example']));
      });
    });
  });
}
