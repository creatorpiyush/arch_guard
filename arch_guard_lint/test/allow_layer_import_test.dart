// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:arch_guard/arch_guard.dart';
import 'package:arch_guard_lint/src/fixes/allow_layer_import.dart';
import 'package:arch_guard_lint/src/layer_violation_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_support.dart';

void main() {
  group('allowLayerImportYaml', () {
    test('appends to an existing list', () {
      expect(
        allowLayerImportYaml(
          'layers:\n  ui:\n    patterns: ["lib/ui/**"]\n'
          '    allowed_imports: [domain]\n',
          layer: 'ui',
          target: 'data',
          currentAllowed: ['domain'],
        ),
        'layers:\n  ui:\n    patterns: ["lib/ui/**"]\n'
        '    allowed_imports: [domain, data]\n',
      );
    });

    test('preset layer not listed: the override keeps the preset list', () {
      final out = allowLayerImportYaml(
        'preset: clean_architecture\n',
        layer: 'presentation',
        target: 'data',
        currentAllowed: ['core', 'domain', 'presentation'],
      )!;
      expect(
        ArchGuardConfig.parse(
          out,
          rootPath: '.',
        ).layers['presentation']!.allowedImports,
        ['core', 'domain', 'presentation', 'data'],
      );
    });

    test('preset with other layers listed', () {
      final out = allowLayerImportYaml(
        'preset: clean_architecture\nlayers:\n  l10n:\n'
        '    patterns: ["lib/l10n/**"]\n',
        layer: 'presentation',
        target: 'data',
        currentAllowed: ['core', 'domain', 'presentation'],
      )!;
      final layers = ArchGuardConfig.parse(out, rootPath: '.').layers;
      expect(layers['presentation']!.allowedImports, contains('data'));
      expect(layers, contains('l10n'));
    });

    test('pubspec: edits only the arch_guard section', () {
      const pubspec =
          'name: app\n'
          'arch_guard:\n'
          '  layers:\n'
          '    ui:\n'
          '      patterns: ["lib/ui/**"]\n'
          'dev_dependencies:\n'
          '  test: any\n';
      final out = allowLayerImportYaml(
        pubspec,
        section: 'arch_guard',
        layer: 'ui',
        target: 'data',
        currentAllowed: [],
      )!;
      expect(out, startsWith('name: app\narch_guard:\n'));
      expect(out, endsWith('dev_dependencies:\n  test: any\n'));
      expect(out, contains('allowed_imports'));
    });

    test('unparseable YAML gives null', () {
      expect(
        allowLayerImportYaml(
          'layers: [:::',
          layer: 'a',
          target: 'b',
          currentAllowed: [],
        ),
        isNull,
      );
    });
  });

  defineReflectiveSuite(() {
    defineReflectiveTests(AllowLayerImportTest);
  });
}

const _config = '''
layers:
  domain:
    patterns: ["lib/domain/**"]
  data:
    patterns: ["lib/data/**"]
    allowed_imports: [domain]
''';

@reflectiveTest
class AllowLayerImportTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = LayerViolationRule();
    super.setUp();
    newFile('$testPackageLibPath/data/repo.dart', 'class Repo {}\n');
  }

  String get _path => '$testPackageLibPath/domain/user_view.dart';

  void test_editsArchGuardYaml() async {
    final config = newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile(_path, "import '../data/repo.dart';\nRepo? r;\n");
    final (out, message) = await applyFix(this, _path, AllowLayerImport.new);
    expect(out.keys, [config.path]);
    expect(
      ArchGuardConfig.parse(
        out[config.path]!,
        rootPath: '.',
      ).layers['domain']!.allowedImports,
      ['data'],
    );
    expect(message, 'Allow layer `domain` to import `data` (arch_guard.yaml)');
  }

  void test_editsPubspecSection() async {
    final pubspec = newFile(
      '$testPackageRootPath/pubspec.yaml',
      'name: test\narch_guard:\n${_config.replaceAll(RegExp('^', multiLine: true), '  ').trimRight()}\n',
    );
    newFile(_path, "import '../data/repo.dart';\nRepo? r;\n");
    final (out, message) = await applyFix(this, _path, AllowLayerImport.new);
    expect(out[pubspec.path], startsWith('name: test\narch_guard:\n'));
    expect(out[pubspec.path], contains('allowed_imports: [data]'));
    expect(message, endsWith('(pubspec.yaml)'));
  }
}
