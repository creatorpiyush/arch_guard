import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
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

    test('honours custom scanDirs with workspace discovery enabled', () async {
      final scanner = ProjectScanner(
        rootPath: 'example/sample_project',
        scanDirs: ['lib/services'],
      );

      final result = await scanner.scan();
      expect(result.isWorkspace, isFalse);
      expect(
        result.files.keys,
        unorderedEquals([
          'lib/services/auth_service.dart',
          'lib/services/session_service.dart',
        ]),
      );
    });

    test('drops edges whose target file was not scanned', () async {
      final scanner = ProjectScanner(
        rootPath: 'example/sample_project',
        scanDirs: ['lib/services'],
        enableWorkspace: false,
      );

      final result = await scanner.scan();
      expect(result.edges, isNotEmpty);
      for (final edge in result.edges) {
        expect(result.files, contains(edge.to), reason: '$edge');
      }
    });

    test(
      'detects a cycle in a Flutter-style conditional import fixture',
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
      },
    );

    group('on disk', () {
      late Directory root;

      setUp(() {
        root = Directory.systemTemp.createTempSync('arch_guard_scan_');
        Directory(p.join(root.path, 'lib')).createSync();
        File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      });

      tearDown(() {
        root.deleteSync(recursive: true);
      });

      test('reports files it cannot read instead of dropping them', () async {
        File(p.join(root.path, 'lib', 'ok.dart')).writeAsStringSync('');
        File(
          p.join(root.path, 'lib', 'bad.dart'),
        ).writeAsBytesSync([0xff, 0xfe, 0xfa, 0x80]);

        final result = await ProjectScanner(rootPath: root.path).scan();
        expect(result.files.keys, equals(['lib/ok.dart']));
        expect(result.skippedFiles.keys, equals(['lib/bad.dart']));
      });

      test('adds library -> part edges but not part-of edges', () async {
        File(
          p.join(root.path, 'lib', 'lib.dart'),
        ).writeAsStringSync("part 'src/piece.dart';\n");
        Directory(p.join(root.path, 'lib', 'src')).createSync();
        File(
          p.join(root.path, 'lib', 'src', 'piece.dart'),
        ).writeAsStringSync("part of '../lib.dart';\n");

        final result = await ProjectScanner(rootPath: root.path).scan();
        expect(result.edges, [
          const GraphEdge(
            from: 'lib/lib.dart',
            to: 'lib/src/piece.dart',
            type: 'part',
          ),
        ]);
        expect(result.files['lib/lib.dart']!.parts, ['src/piece.dart']);
        expect(
          DependencyGraph.fromScanResult(result).findCircularDependencies(),
          isEmpty,
        );
      });
    });
  });

  group('ProjectScanner package imports', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('arch_guard_pkg_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String path, String content) {
      final file = File(p.join(dir.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test(
      'records package: and dart: directives but not self-imports',
      () async {
        write('pubspec.yaml', 'name: app\n');
        write('lib/b.dart', '');
        write('lib/a.dart', """
import 'package:app/b.dart';
import 'package:dio/dio.dart';
import 'dart:io';
export 'package:meta/meta.dart';
import 'b.dart';
""");

        final result = await ProjectScanner(rootPath: dir.path).scan();
        final imports = result.packageImports
            .map((i) => '${i.file}|${i.package}|${i.type}|${i.line}')
            .toList();
        expect(
          imports,
          equals([
            'lib/a.dart|dio|import|2',
            'lib/a.dart|dart:io|import|3',
            'lib/a.dart|meta|export|4',
          ]),
        );
      },
    );

    test(
      'records imports of other workspace packages, not of the own one',
      () async {
        write(
          'pubspec.yaml',
          'name: root\nworkspace:\n  - packages/auth\n  - packages/ui\n',
        );
        write(
          'packages/auth/pubspec.yaml',
          'name: auth\nresolution: workspace\n',
        );
        write('packages/ui/pubspec.yaml', 'name: ui\nresolution: workspace\n');
        write('packages/ui/lib/button.dart', '');
        write('packages/auth/lib/x.dart', '');
        write('packages/auth/lib/login.dart', """
import 'package:auth/x.dart';
import 'package:ui/button.dart';
""");

        final result = await ProjectScanner(rootPath: dir.path).scan();
        expect(
          result.packageImports.map((i) => '${i.file}|${i.package}'),
          equals(['packages/auth/lib/login.dart|ui']),
        );
      },
    );

    test('packageOf reads package and dart library names', () {
      expect(PackageImport.packageOf('package:dio/dio.dart'), 'dio');
      expect(PackageImport.packageOf('dart:io'), 'dart:io');
      expect(PackageImport.packageOf('dart:ui'), 'dart:ui');
      expect(PackageImport.packageOf('../data/repo.dart'), isNull);
      expect(PackageImport.packageOf('package:broken'), isNull);
    });
  });
}
