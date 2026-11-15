import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _modules = '''
modules:
  roots: [lib/features/*]
''';

ArchGuardConfig _config(String yaml) =>
    ArchGuardConfig.parse(yaml, rootPath: Directory.systemTemp.path);

List<ModuleViolation> _check(
  Map<String, String> sources, {
  String yaml = _modules,
}) => ModuleValidator.validate(
  result: ProjectScanner.scanSources(packageName: 'app', sources: sources),
  config: _config(yaml),
);

void main() {
  group('ModuleValidator', () {
    test('a private file of another module fails, a public one passes', () {
      final violations = _check({
        'lib/features/checkout/page.dart':
            "import '../cart/data/cart_repo.dart';\n"
            "import '../cart/cart.dart';\n",
        'lib/features/cart/cart.dart': '',
        'lib/features/cart/data/cart_repo.dart': '',
      });
      final v = violations.single;
      expect(v.sourceModule, 'checkout');
      expect(v.targetModule, 'cart');
      expect(v.targetFile, 'lib/features/cart/data/cart_repo.dart');
      expect(v.line, 1);
      expect(v.notAllowed, isFalse);
      expect(
        v.rule,
        'Other modules may import `cart` only through '
        'lib/features/cart/*.dart.',
      );
      expect(
        v.toString(),
        '❌ Module Violation: [checkout] lib/features/checkout/page.dart:1 '
        '-> [cart] lib/features/cart/data/cart_repo.dart',
      );
    });

    test('imports inside one module are never violations', () {
      expect(
        _check({
          'lib/features/cart/ui/page.dart': "import '../data/repo.dart';\n",
          'lib/features/cart/data/repo.dart': '',
        }),
        isEmpty,
      );
    });

    test('a public barrel that re-exports private files is the way in', () {
      // Unlike layers, which look through barrels, a module's own barrel
      // is exactly the path other modules should use.
      expect(
        _check({
          'lib/features/checkout/page.dart': "import '../cart/cart.dart';\n",
          'lib/features/cart/cart.dart': "export 'data/repo.dart';\n",
          'lib/features/cart/data/repo.dart': '',
        }),
        isEmpty,
      );
    });

    test('allowed restricts which modules may be imported at all', () {
      final violations = _check(
        {
          'lib/features/checkout/page.dart':
              "import '../cart/cart.dart';\n"
              "import '../profile/profile.dart';\n",
          'lib/features/cart/cart.dart': '',
          'lib/features/profile/profile.dart': '',
          // Not listed under allowed: may import any module.
          'lib/features/profile/x.dart': "import '../checkout/page.dart';\n",
        },
        yaml: '''
modules:
  roots: [lib/features/*]
  allowed:
    checkout: [cart]
''',
      );
      final v = violations.single;
      expect(v.targetModule, 'profile');
      expect(v.notAllowed, isTrue);
      expect(v.rule, '`checkout` may only import modules `cart`.');
      expect(v.toJson()['reason'], 'not_allowed');
    });

    test('files outside every module are unrestricted both ways', () {
      expect(
        _check({
          'lib/main.dart': "import 'features/cart/data/repo.dart';\n",
          'lib/features/cart/data/repo.dart':
              "import '../../../core/x.dart';\n",
          'lib/core/x.dart': '',
        }),
        isEmpty,
      );
    });

    test('public globs are relative to the module folder', () {
      final violations = _check(
        {
          'lib/features/checkout/page.dart':
              "import '../cart/api/cart_api.dart';\n"
              "import '../cart/cart.dart';\n",
          'lib/features/cart/cart.dart': '',
          'lib/features/cart/api/cart_api.dart': '',
        },
        yaml: '''
modules:
  roots: [lib/features/*]
  public: ["api/**"]
''',
      );
      expect(violations.single.targetFile, 'lib/features/cart/cart.dart');
    });

    test('roots match from a workspace member lib/, like layer patterns', () {
      final violations = _check({
        'packages/app/lib/features/a/a.dart': "import '../b/src/b.dart';\n",
        'packages/app/lib/features/b/src/b.dart': '',
      });
      expect(violations.single.sourceModule, 'a');
      expect(violations.single.targetModule, 'b');
      expect(
        violations.single.rule,
        contains('packages/app/lib/features/b/*.dart'),
      );
    });

    test('an ignore comment silences the import', () {
      expect(
        _check({
          'lib/features/a/a.dart':
              '// ignore: arch_guard_lint/module_violation\n'
              "import '../b/src/b.dart';\n",
          'lib/features/b/src/b.dart': '',
        }),
        isEmpty,
      );
    });

    test(
      'one import can break a layer rule, a module rule, both or neither',
      () {
        const yaml = '''
layers:
  domain:
    patterns: ["lib/features/*/domain/**"]
    allowed_imports: []
  data:
    patterns: ["lib/features/*/data/**"]
    allowed_imports: [domain]
modules:
  roots: [lib/features/*]
''';
        final sources = {
          // both: domain -> data, into another module's private file
          'lib/features/a/domain/x.dart': "import '../../b/data/y.dart';\n",
          // module only: data -> domain is allowed, but private
          'lib/features/a/data/y.dart': "import '../../b/domain/x.dart';\n",
          // layer only: inside one module
          'lib/features/b/domain/x.dart': "import '../data/y.dart';\n",
          // neither
          'lib/features/b/data/y.dart': "import '../domain/x.dart';\n",
        };
        final result = ProjectScanner.scanSources(
          packageName: 'app',
          sources: sources,
        );
        final config = _config(yaml);
        String key(String from, String to) => '$from -> $to';
        final layer = {
          for (final v in LayerValidator.validate(
            result: result,
            config: config,
          ))
            key(v.sourceFile, v.targetFile),
        };
        final module = {
          for (final v in ModuleValidator.validate(
            result: result,
            config: config,
          ))
            key(v.sourceFile, v.targetFile),
        };
        expect(layer, {
          key('lib/features/a/domain/x.dart', 'lib/features/b/data/y.dart'),
          key('lib/features/b/domain/x.dart', 'lib/features/b/data/y.dart'),
        });
        expect(module, {
          key('lib/features/a/domain/x.dart', 'lib/features/b/data/y.dart'),
          key('lib/features/a/data/y.dart', 'lib/features/b/domain/x.dart'),
        });
      },
    );
  });

  group('config', () {
    test('defaults public to the files directly in the module folder', () {
      final m = _config(_modules).modules!;
      expect(m.roots, ['lib/features/*']);
      expect(m.public, ['*.dart']);
      expect(m.allowed, isEmpty);
    });

    test('warns about unknown keys and a missing roots list', () {
      final config = _config('''
modules:
  public: ["*.dart"]
  root: [lib/features/*]
''');
      expect(config.modules, isNull);
      expect(config.warnings, [
        contains('unknown key `modules: root`'),
        contains('`modules` needs a `roots:` list'),
      ]);
    });

    test('warns about roots and allowed names that match nothing', () {
      final config = _config('''
modules:
  roots: [lib/features/*, lib/feature/*]
  allowed:
    cart: [chekout]
''');
      final warnings = ModuleValidator.warnings(
        result: ProjectScanner.scanSources(
          packageName: 'app',
          sources: {'lib/features/cart/cart.dart': ''},
        ),
        config: config,
      );
      expect(warnings, [
        contains('root `lib/feature/*` matches no folder'),
        contains('`chekout`, which is not a module'),
      ]);
    });

    test('names no allowed entries when no root matched at all', () {
      final warnings = ModuleValidator.warnings(
        result: ProjectScanner.scanSources(
          packageName: 'app',
          sources: {'lib/features/cart/cart.dart': ''},
        ),
        config: _config('''
modules:
  roots: [lib/feature/*]
  allowed:
    cart: [checkout]
'''),
      );
      expect(warnings, [contains('root `lib/feature/*` matches no folder')]);
    });
  });

  group('ArchAnalysis', () {
    late Directory project;

    void write(String path, String content) {
      final file = File(p.join(project.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    void git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: project.path);
      if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
    }

    setUp(() {
      project = Directory.systemTemp.createTempSync('arch_guard_modules_');
      write('pubspec.yaml', 'name: app\n');
      write('arch_guard.yaml', _modules);
      write('lib/features/a/a.dart', "import '../b/src/b.dart';\n");
      write('lib/features/b/src/b.dart', '');
    });

    tearDown(() => project.deleteSync(recursive: true));

    test('a module violation fails the run', () async {
      final analysis = await ArchAnalysis.run(projectPath: project.path);
      expect(analysis.moduleViolations, hasLength(1));
      expect(analysis.failures(), [
        startsWith('Module boundary: lib/features/a/a.dart:1 (a) imports'),
      ]);
    });

    test(
      'the baseline hides a known violation and reports a new one',
      () async {
        final first = await ArchAnalysis.run(projectPath: project.path);
        Baseline.capture(
          cycles: first.cycles,
          layerViolations: first.layerViolations,
          moduleViolations: first.moduleViolations,
        ).save(first.baselinePath);

        final known = await ArchAnalysis.run(projectPath: project.path);
        expect(known.failures(), isEmpty);
        expect(known.baseline!.knownModuleViolations, hasLength(1));

        write('lib/features/c/c.dart', "import '../b/src/b.dart';\n");
        final added = await ArchAnalysis.run(projectPath: project.path);
        expect(
          added.newModuleViolations.single.sourceFile,
          'lib/features/c/c.dart',
        );

        write('lib/features/a/a.dart', '');
        File(p.join(project.path, 'lib/features/c/c.dart')).deleteSync();
        final fixed = await ArchAnalysis.run(projectPath: project.path);
        expect(fixed.baseline!.fixedModuleViolationCount, 1);
      },
    );

    test('--since keeps only violations from changed files', () async {
      git(['init', '-q', '-b', 'main']);
      git(['config', 'user.email', 't@example.com']);
      git(['config', 'user.name', 'T']);
      git(['add', '.']);
      git(['commit', '-qm', 'base']);
      write('lib/features/c/c.dart', "import '../b/src/b.dart';\n");
      final analysis = await ArchAnalysis.run(
        projectPath: project.path,
        since: 'main',
      );
      expect(
        analysis.moduleViolations.single.sourceFile,
        'lib/features/c/c.dart',
      );
    });
  });
}
