import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProjectScanner', () {
    test('scanSources matches scan() for the same files', () async {
      final disk = await ProjectScanner(
        rootPath: 'example/cases/cycles',
      ).scan();
      final sources = {
        for (final f in disk.files.keys)
          f: File('example/cases/cycles/$f').readAsStringSync(),
      };
      final mem = ProjectScanner.scanSources(
        packageName: 'cycles',
        sources: sources,
      );
      String edges(ScanResult r) =>
          r.edges.map((e) => '${e.from}>${e.to}:${e.type}:${e.line}').join(',');
      expect(mem.files.keys, disk.files.keys);
      expect(edges(mem), edges(disk));
    });

    test('scanSources resolves self package imports and parts', () {
      final r = ProjectScanner.scanSources(
        packageName: 'app',
        sources: {
          'lib/a.dart': "import 'package:app/b.dart';\npart 'a_part.dart';\n",
          'lib/a_part.dart': "part of 'a.dart';\n",
          'lib/b.dart': "import 'package:other/x.dart';\n",
        },
      );
      expect(r.edges.map((e) => '${e.from}>${e.to}:${e.type}'), [
        'lib/a.dart>lib/a_part.dart:part',
        'lib/a.dart>lib/b.dart:import',
      ]);
      expect(r.packageImports.single.package, 'other');
    });

    test('scans sample_project fixture correctly', () async {
      final scanner = ProjectScanner(
        rootPath: 'example/cases/sample_project',
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
        rootPath: 'example/cases/sample_project',
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
        rootPath: 'example/cases/sample_project',
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

  test(
    'scan order is deterministic: sorted files and edges, stable cycles',
    () async {
      final outputs = <String>[];
      for (var i = 0; i < 5; i++) {
        final result = await ProjectScanner(
          rootPath: 'example/cases/sample_project',
        ).scan();
        expect(result.files.keys.toList(), [...result.files.keys]..sort());
        final edgeKeys = result.edges.map((e) => '${e.from}|${e.to}').toList();
        expect(edgeKeys, [...edgeKeys]..sort());
        final cycles = DependencyGraph.fromScanResult(
          result,
        ).findCircularDependencies();
        outputs.add(cycles.map((c) => c.exampleChain.join('>')).join('\n'));
      }
      expect(outputs.toSet(), hasLength(1));
    },
  );

  test('nested workspace members own their files (longest path wins)', () async {
    final dir = Directory.systemTemp.createTempSync('arch_guard_nested_');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String path, String content) {
      final file = File(p.join(dir.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - packages/a\n  - packages/a/nested/inner\n',
    );
    write('packages/a/pubspec.yaml', 'name: a\n');
    write('packages/a/lib/a.dart', '');
    write('packages/a/nested/inner/pubspec.yaml', 'name: inner\n');
    write('packages/a/nested/inner/lib/j.dart', '');
    write(
      'packages/a/nested/inner/lib/i.dart',
      "import 'package:inner/j.dart';\n",
    );

    final result = await ProjectScanner(rootPath: dir.path).scan();
    // A self-import of `inner` is not an external package import.
    expect(result.packageImports, isEmpty);
    expect(
      result.edges.map((e) => '${e.from}>${e.to}'),
      contains(
        'packages/a/nested/inner/lib/i.dart>packages/a/nested/inner/lib/j.dart',
      ),
    );
  });
}
