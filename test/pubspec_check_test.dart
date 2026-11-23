import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  void write(String path, String content) {
    final f = File(p.join(dir.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  setUp(() => dir = Directory.systemTemp.createTempSync('arch_guard_deps_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<PubspecCheckResult> check([String config = 'pubspec_check: {}\n']) =>
      PubspecCheck.run(
        projectRoot: dir.path,
        config: ArchGuardConfig.parse(config, rootPath: dir.path),
      );

  List<String> keys(PubspecCheckResult r) => [
    for (final x in r.problems) x.key,
  ];

  test('unused dependency is reported with its line', () async {
    write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  path: any\n  dio: any\n',
    );
    write('lib/a.dart', "import 'package:path/path.dart';\n");
    final r = await check();
    final x = r.problems.single;
    expect(x.key, 'pubspec.yaml: dio (unused)');
    expect(x.kind, 'unused');
    expect(x.package, 'app');
    expect(x.line, 4);
    expect(x.rule, contains('`dio` is under dependencies'));
  });

  test('misplaced: used only from test/', () async {
    write('pubspec.yaml', 'name: app\ndependencies:\n  mocktail: any\n');
    write('lib/a.dart', '');
    write('test/a_test.dart', "import 'package:mocktail/mocktail.dart';\n");
    final r = await check();
    expect(keys(r), ['pubspec.yaml: mocktail (misplaced)']);
    expect(r.problems.single.rule, contains('move it to dev_dependencies'));
  });

  test('used from lib/, bin/ and hook/ is fine', () async {
    write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  a: any\n  b: any\n  c: any\n',
    );
    write('lib/x.dart', "import 'package:a/a.dart';\n");
    write('bin/main.dart', "import 'package:b/b.dart';\n");
    write('hook/build.dart', "export 'package:c/c.dart';\n");
    expect(keys(await check()), isEmpty);
  });

  test('analysis_options include counts as use', () async {
    write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  very_good_analysis: any\n',
    );
    write(
      'analysis_options.yaml',
      'include: package:very_good_analysis/analysis_options.yaml\n',
    );
    expect(keys(await check()), isEmpty);
  });

  test('sdk entries, cupertino_icons and ignore: are skipped', () async {
    write('pubspec.yaml', '''
name: app
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  cupertino_icons: any
  x: any
''');
    final r = await check('pubspec_check:\n  ignore: [x]\n');
    expect(keys(r), isEmpty);
    expect(r.warnings, isEmpty);
  });

  test('dev_dependencies are never reported', () async {
    write(
      'pubspec.yaml',
      'name: app\ndev_dependencies:\n  build_runner: any\n  lints: any\n',
    );
    expect(keys(await check()), isEmpty);
  });

  test('generated and stub files count as use', () async {
    write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  json_annotation: any\n  web: any\n',
    );
    write(
      'lib/a.g.dart',
      "import 'package:json_annotation/json_annotation.dart';\n",
    );
    write('lib/stub/s.dart', "import 'package:web/web.dart';\n");
    expect(keys(await check()), isEmpty);
  });

  test('workspace: per member, nested example app excluded, bin-only member '
      'checked', () async {
    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - packages/a\n  - apps/cli\n',
    );
    write(
      'packages/a/pubspec.yaml',
      'name: a\nresolution: workspace\ndependencies:\n  dio: any\n  http: any\n',
    );
    write('packages/a/lib/a.dart', "import 'package:dio/dio.dart';\n");
    write('packages/a/example/pubspec.yaml', 'name: a_example\n');
    write(
      'packages/a/example/lib/main.dart',
      "import 'package:http/http.dart';\n",
    );
    write(
      'apps/cli/pubspec.yaml',
      'name: cli\nresolution: workspace\ndependencies:\n  args: any\n',
    );
    write('apps/cli/bin/main.dart', '');
    expect(keys(await check()), [
      'apps/cli/pubspec.yaml: args (unused)',
      'packages/a/pubspec.yaml: http (unused)',
    ]);
  });

  test('a dependency used by one member does not count for another', () async {
    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - packages/a\n  - packages/b\n',
    );
    write('packages/a/pubspec.yaml', 'name: a\ndependencies:\n  dio: any\n');
    write('packages/a/lib/a.dart', "import 'package:dio/dio.dart';\n");
    write('packages/b/pubspec.yaml', 'name: b\ndependencies:\n  dio: any\n');
    write('packages/b/lib/b.dart', '');
    expect(keys(await check()), ['packages/b/pubspec.yaml: dio (unused)']);
  });

  test('malformed pubspec is skipped with a warning', () async {
    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - packages/a\n  - packages/b\n',
    );
    write('packages/a/pubspec.yaml', 'name: a\ndependencies: [oops\n');
    write('packages/a/lib/a.dart', '');
    write('packages/b/pubspec.yaml', 'name: b\ndependencies:\n  dio: any\n');
    write('packages/b/lib/b.dart', '');
    final r = await check();
    expect(keys(r), ['packages/b/pubspec.yaml: dio (unused)']);
    expect(
      r.warnings,
      contains(startsWith('pubspec_check: skipped packages/a/pubspec.yaml: ')),
    );
  });

  test('ignore entry that matches nothing warns', () async {
    write('pubspec.yaml', 'name: app\n');
    final r = await check('pubspec_check:\n  ignore: [ghost]\n');
    expect(
      r.warnings,
      contains(
        'pubspec_check: ignore: `ghost` is not a dependency of any package.',
      ),
    );
  });

  test('federated plugin platform packages count as used', () async {
    write('pubspec.yaml', '''
name: foo
dependencies:
  foo_android: any
  foo_ios: any
flutter:
  plugin:
    platforms:
      android:
        default_package: foo_android
      ios:
        default_package: foo_ios
''');
    write('lib/foo.dart', '');
    expect(keys(await check()), isEmpty);
  });

  test('intl counts as used with flutter: generate: true', () async {
    write(
      'pubspec.yaml',
      'name: app\ndependencies:\n  intl: any\nflutter:\n  generate: true\n',
    );
    write('lib/main.dart', '');
    expect(keys(await check()), isEmpty);
  });

  test('imports from web/ count as runtime use', () async {
    write('pubspec.yaml', 'name: app\ndependencies:\n  web: any\n');
    write('web/main.dart', "import 'package:web/web.dart';\n");
    expect(keys(await check()), isEmpty);
  });

  test('packages used through assets or fonts count as used', () async {
    write(
      '''pubspec.yaml''',
      '''
name: app
dependencies:
  icon_pack: any
  font_pack: any
flutter:
  assets:
    - packages/icon_pack/icons/star.png
  fonts:
    - family: Brand
      fonts:
        - asset: packages/font_pack/fonts/Brand.ttf
''',
    );
    write('lib/main.dart', '');
    expect(keys(await check()), isEmpty);
  });

  test('toJson', () async {
    write('pubspec.yaml', 'name: app\ndependencies:\n  dio: any\n');
    final x = (await check()).problems.single;
    expect(x.toJson(), {
      'package': 'app',
      'pubspec': 'pubspec.yaml',
      'dependency': 'dio',
      'kind': 'unused',
      'line': 3,
      'rule': x.rule,
    });
  });

  group('in ArchAnalysis', () {
    void project({bool fail = false}) {
      write('pubspec.yaml', 'name: app\ndependencies:\n  dio: any\n');
      write('lib/a.dart', '');
      write('arch_guard.yaml', 'pubspec_check:\n  fail: $fail\n');
    }

    test('report-only by default', () async {
      project();
      final a = await ArchAnalysis.run(projectPath: dir.path);
      expect(a.dependencyProblems.single.dependency, 'dio');
      expect(a.newDependencyProblems, hasLength(1));
      expect(a.failures(), isEmpty);
    });

    test('fail: true fails on new problems', () async {
      project(fail: true);
      final a = await ArchAnalysis.run(projectPath: dir.path);
      expect(a.failures(), [startsWith('Dependency: `dio` is under')]);
    });

    test('off without pubspec_check', () async {
      write('pubspec.yaml', 'name: app\ndependencies:\n  dio: any\n');
      write('lib/a.dart', '');
      final a = await ArchAnalysis.run(projectPath: dir.path);
      expect(a.dependencyProblems, isEmpty);
    });

    test('baseline hides a known problem and counts a fixed one', () async {
      project(fail: true);
      final first = await ArchAnalysis.run(projectPath: dir.path);
      Baseline.capture(
        cycles: const [],
        layerViolations: const [],
        dependencyProblems: first.dependencyProblems,
      ).save(p.join(dir.path, defaultBaselineFileName));
      final known = await ArchAnalysis.run(projectPath: dir.path);
      expect(known.newDependencyProblems, isEmpty);
      expect(known.baseline!.knownDependencyProblems, hasLength(1));
      expect(known.failures(), isEmpty);

      write('pubspec.yaml', 'name: app\n');
      final fixed = await ArchAnalysis.run(projectPath: dir.path);
      expect(fixed.baseline!.fixedDependencyProblemCount, 1);
    });

    test('--since keeps only problems in changed packages', () async {
      void git(List<String> args) {
        final r = Process.runSync('git', args, workingDirectory: dir.path);
        if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
      }

      write(
        'pubspec.yaml',
        'name: root\nworkspace:\n  - packages/a\n  - packages/b\n',
      );
      write('arch_guard.yaml', 'pubspec_check: {}\n');
      write('packages/a/pubspec.yaml', 'name: a\ndependencies:\n  dio: any\n');
      write('packages/a/lib/a.dart', '');
      write('packages/b/pubspec.yaml', 'name: b\ndependencies:\n  http: any\n');
      write('packages/b/lib/b.dart', '');
      git(['init', '-q', '-b', 'main']);
      git(['config', 'user.email', 't@example.com']);
      git(['config', 'user.name', 'T']);
      git(['add', '.']);
      git(['commit', '-qm', 'base']);
      write(
        'packages/b/pubspec.yaml',
        'name: b\ndependencies:\n  http: any\n  args: any\n',
      );
      final a = await ArchAnalysis.run(projectPath: dir.path, since: 'main');
      expect(
        [for (final x in a.dependencyProblems) x.key],
        [
          'packages/b/pubspec.yaml: args (unused)',
          'packages/b/pubspec.yaml: http (unused)',
        ],
      );
    });
  });
}
