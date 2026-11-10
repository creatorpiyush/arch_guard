import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

AffectedResult _find(Map<String, String> sources, Set<String> changed) =>
    AffectedFiles.find(
      result: ProjectScanner.scanSources(packageName: 'app', sources: sources),
      changed: changed,
    );

void main() {
  test('changed lib file lists the tests that reach it', () {
    final r = _find(
      {
        'lib/a.dart': '',
        'lib/b.dart': "import 'a.dart';",
        'test/b_test.dart': "import 'package:app/b.dart';",
        'test/other_test.dart': '',
      },
      {'lib/a.dart'},
    );
    expect(r.tests, ['test/b_test.dart']);
    expect(r.files, ['lib/a.dart', 'lib/b.dart', 'test/b_test.dart']);
    expect(r.packages.map((p) => p.name), ['app']);
  });

  test('changed test file lists itself', () {
    final r = _find(
      {'lib/a.dart': '', 'test/a_test.dart': "import 'package:app/a.dart';"},
      {'test/a_test.dart'},
    );
    expect(r.tests, ['test/a_test.dart']);
    expect(r.files, ['test/a_test.dart']);
  });

  test('test helper change lists tests importing it', () {
    final r = _find(
      {
        'test/helpers.dart': '',
        'test/a_test.dart': "import 'helpers.dart';",
        'test/b_test.dart': '',
      },
      {'test/helpers.dart'},
    );
    expect(r.tests, ['test/a_test.dart']);
    expect(r.files, contains('test/helpers.dart'));
  });

  test('ignored and conditional edges still count', () {
    final r = _find(
      {
        'lib/a.dart': '',
        'lib/io.dart': '',
        'lib/stub.dart': '',
        'lib/b.dart': '''
// ignore: arch_guard_lint/circular_dependency
import 'a.dart';
import 'stub.dart' if (dart.library.io) 'io.dart';
''',
        'test/b_test.dart': "import 'package:app/b.dart';",
      },
      {'lib/a.dart', 'lib/io.dart'},
    );
    expect(r.tests, ['test/b_test.dart']);
    expect(r.files, contains('lib/b.dart'));
  });

  test("part change reaches the library's dependents", () {
    final r = _find(
      {
        'lib/lib.dart': "part 'p.dart';",
        'lib/p.dart': "part of 'lib.dart';",
        'test/lib_test.dart': "import 'package:app/lib.dart';",
      },
      {'lib/p.dart'},
    );
    expect(r.tests, ['test/lib_test.dart']);
  });

  test('deleted file lists its importers', () {
    final r = _find(
      {
        'lib/a.dart': '',
        'test/gone_test.dart': "import 'package:app/gone.dart';",
        'test/a_test.dart': "import 'package:app/a.dart';",
      },
      {'lib/gone.dart'},
    );
    expect(r.tests, ['test/gone_test.dart']);
    expect(r.ignoredChanges, isEmpty);
  });

  test('changed generated file lists its library', () {
    final r = _find(
      {
        'lib/m.dart': "part 'm.g.dart';",
        'test/m_test.dart': "import 'package:app/m.dart';",
      },
      {'lib/m.g.dart'},
    );
    expect(r.files, contains('lib/m.dart'));
    expect(r.tests, ['test/m_test.dart']);
  });

  test('pubspec change affects the whole package', () {
    final r = _find(
      {'lib/a.dart': '', 'test/a_test.dart': '', 'test/b_test.dart': ''},
      {'pubspec.lock'},
    );
    expect(r.tests, ['test/a_test.dart', 'test/b_test.dart']);
    expect(r.files, hasLength(3));
  });

  test('non-Dart changes are ignored', () {
    final r = _find({'lib/a.dart': ''}, {'assets/logo.png', 'README.md'});
    expect(r.ignoredChanges, ['README.md', 'assets/logo.png']);
    expect(r.files, isEmpty);
    expect(r.packages, isEmpty);
  });

  group('workspace', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('affected_ws'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String path, String content) {
      final f = File(p.join(root.path, path));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    Future<ScanResult> scan() => ProjectScanner(
      rootPath: root.path,
      scanDirs: const ['lib', 'test'],
      memberScanDirs: const ['lib', 'test'],
    ).scan();

    test('workspace change crosses members', () async {
      write(
        'pubspec.yaml',
        'name: root\nworkspace:\n  - packages/*\n  - apps/*\n',
      );
      write('packages/core/pubspec.yaml', 'name: core\n');
      write('packages/core/lib/x.dart', '');
      write('apps/app/pubspec.yaml', 'name: app\n');
      write('apps/app/lib/main.dart', '');
      write('apps/app/test/y_test.dart', "import 'package:core/x.dart';");
      write('apps/app/test/z_test.dart', "import 'package:app/main.dart';");

      final r = AffectedFiles.find(
        result: await scan(),
        changed: {'packages/core/lib/x.dart'},
      );
      expect(r.tests, ['apps/app/test/y_test.dart']);
      expect(r.packages.map((p) => p.name), ['app', 'core']);
    });

    test('member pubspec change affects only that member', () async {
      write('pubspec.yaml', 'name: root\nworkspace:\n  - packages/*\n');
      write('packages/a/pubspec.yaml', 'name: a\n');
      write('packages/a/lib/a.dart', '');
      write('packages/a/test/a_test.dart', '');
      write('packages/b/pubspec.yaml', 'name: b\n');
      write('packages/b/lib/b.dart', '');
      write('packages/b/test/b_test.dart', '');

      final r = AffectedFiles.find(
        result: await scan(),
        changed: {'packages/a/pubspec.yaml'},
      );
      expect(r.tests, ['packages/a/test/a_test.dart']);
      expect(r.packages.map((p) => p.name), ['a']);
    });
  });
}
