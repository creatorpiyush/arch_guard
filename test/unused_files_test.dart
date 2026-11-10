import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  ({List<String> files, bool noEntryPoint}) find(
    Map<String, String> sources, {
    List<String> entryPoints = const [],
  }) => UnusedFiles.find(
    result: ProjectScanner.scanSources(packageName: 'app', sources: sources),
    entryPoints: entryPoints,
  );

  test('main reaches imports and exports', () {
    final r = find({
      'lib/main.dart': "import 'a.dart';",
      'lib/a.dart': "export 'b.dart';",
      'lib/b.dart': '',
      'lib/c.dart': '',
    });
    expect(r.files, ['lib/c.dart']);
    expect(r.noEntryPoint, isFalse);
  });

  test('dead cycle is reported', () {
    final r = find({
      'lib/main.dart': '',
      'lib/x.dart': "import 'y.dart';",
      'lib/y.dart': "import 'x.dart';",
    });
    expect(r.files, ['lib/x.dart', 'lib/y.dart']);
  });

  test('flavour mains are all entry points', () {
    final r = find({
      'lib/main_dev.dart': "import 'dev.dart';",
      'lib/main_prod.dart': "import 'prod.dart';",
      'lib/dev.dart': '',
      'lib/prod.dart': '',
    });
    expect(r.files, isEmpty);
    expect(r.noEntryPoint, isFalse);
  });

  test('package barrel is an entry point', () {
    final r = find({
      'lib/app.dart': "export 'src/a.dart';",
      'lib/src/a.dart': '',
    });
    expect(r.files, isEmpty);
    expect(r.noEntryPoint, isFalse);
  });

  test('part file is reachable', () {
    final r = find({
      'lib/main.dart': "part 'main.g.dart';",
      'lib/main.g.dart': "part of 'main.dart';",
    });
    expect(r.files, isEmpty);
  });

  test('conditional import targets are reachable', () {
    final r = find({
      'lib/main.dart': "import 'stub.dart' if (dart.library.io) 'io.dart';",
      'lib/stub.dart': '',
      'lib/io.dart': '',
    });
    expect(r.files, isEmpty);
  });

  test('extra entry point', () {
    final r = find(
      {'lib/main.dart': '', 'lib/router.dart': ''},
      entryPoints: ['lib/router.dart'],
    );
    expect(r.files, isEmpty);
  });

  test('no entry point reports nothing', () {
    final r = find({'lib/a.dart': '', 'lib/b.dart': ''});
    expect(r.noEntryPoint, isTrue);
    expect(r.files, isEmpty);
  });

  test('workspace: member barrel and cross-member imports count', () async {
    final dir = Directory.systemTemp.createTempSync('arch_guard_unused_');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String path, String content) {
      final file = File(p.join(dir.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - packages/core\n  - apps/shop\n',
    );
    write('packages/core/pubspec.yaml', 'name: core\nresolution: workspace\n');
    write('apps/shop/pubspec.yaml', 'name: shop\nresolution: workspace\n');
    write('packages/core/lib/core.dart', '');
    write('packages/core/lib/src/util.dart', '');
    write('packages/core/lib/src/dead.dart', '');
    write('apps/shop/lib/main.dart', "import 'package:core/src/util.dart';\n");

    final result = await ProjectScanner(rootPath: dir.path).scan();
    final r = UnusedFiles.find(result: result);
    expect(r.files, ['packages/core/lib/src/dead.dart']);
  });

  test('main-like names are not entry points', () {
    final r = find({
      'lib/main.dart': '',
      'lib/maintenance.dart': '',
      'lib/mainframe/x.dart': '',
    });
    expect(r.files, ['lib/mainframe/x.dart', 'lib/maintenance.dart']);
  });

  test('package: self-imports and relative ../ imports count', () {
    final r = find({
      'lib/main.dart': "import 'package:app/src/a.dart';",
      'lib/src/a.dart': "import '../src/deep/b.dart';",
      'lib/src/deep/b.dart': '',
    });
    expect(r.files, isEmpty);
  });

  test('self-import and a dead file importing a used one', () {
    final r = find({
      'lib/main.dart': "import 'used.dart';",
      'lib/used.dart': '',
      'lib/self.dart': "import 'self.dart';",
      'lib/dead.dart': "import 'used.dart';",
    });
    expect(r.files, ['lib/dead.dart', 'lib/self.dart']);
  });

  test('bin, test, tool, example and *_test.dart are entry points', () {
    final r = find({
      'bin/cli.dart': "import 'package:app/src/a.dart';",
      'lib/src/a.dart': '',
      'test/helpers.dart': "import 'package:app/src/b.dart';",
      'lib/src/b.dart': '',
      'tool/gen.dart': "import 'package:app/src/c.dart';",
      'lib/src/c.dart': '',
      'example/demo.dart': "import 'package:app/src/d.dart';",
      'lib/src/d.dart': '',
      'integration/x_test.dart': "import 'package:app/src/e.dart';",
      'lib/src/e.dart': '',
      'lib/src/dead.dart': '',
    });
    expect(r.files, ['lib/src/dead.dart']);
  });

  test('entry point globs can name a folder', () {
    final r = find(
      {
        'lib/main.dart': '',
        'lib/plugins/a.dart': "import 'b.dart';",
        'lib/plugins/b.dart': '',
      },
      entryPoints: ['lib/plugins/**'],
    );
    expect(r.files, isEmpty);
  });

  test('a long chain is followed without recursion limits', () {
    const n = 20000;
    final r = find({
      'lib/main.dart': "import 'f0.dart';",
      for (var i = 0; i < n; i++)
        'lib/f$i.dart': i + 1 < n ? "import 'f${i + 1}.dart';" : '',
      'lib/dead.dart': '',
    });
    expect(r.files, ['lib/dead.dart']);
  });

  test('a test/ folder inside lib/ is no entry point', () {
    final r = find({
      'lib/main.dart': '',
      'lib/features/test/x.dart': '',
      'integration_test/app_test.dart': "import 'package:app/src/y.dart';",
      'lib/src/y.dart': '',
    });
    expect(r.files, ['lib/features/test/x.dart']);
  });
}
