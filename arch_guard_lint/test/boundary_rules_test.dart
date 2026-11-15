// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:arch_guard_lint/src/boundary_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ModuleViolationRuleTest);
    defineReflectiveTests(WorkspaceViolationRuleTest);
  });
}

const _modules = '''
modules:
  roots: [lib/features/*]
''';

// `// ignore: arch_guard_lint/<code>` is applied by the analysis server, which
// AnalysisRuleTest does not model; the CLI side of those codes is tested in
// the arch_guard package.

// Each source uses what it imports, so no `unused_import` warning shows up.
const _privateImport = "import '../cart/data/repo.dart';\nRepo? r;\n";

@reflectiveTest
class ModuleViolationRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ModuleViolationRule();
    super.setUp();
    newFile('$testPackageLibPath/features/cart/cart.dart', 'class Cart {}\n');
    newFile(
      '$testPackageLibPath/features/cart/data/repo.dart',
      'class Repo {}\n',
    );
  }

  String get _pagePath => '$testPackageLibPath/features/checkout/page.dart';

  void test_reportsPrivateFileOfAnotherModule() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _modules);
    newFile(_pagePath, _privateImport);
    await assertDiagnosticsInFile(_pagePath, [
      lint(
        _privateImport.indexOf("'"),
        "'../cart/data/repo.dart'".length,
        messageContainsAll: ['`checkout`', '`cart`', 'only through'],
      ),
    ]);
  }

  void test_publicFileIsQuiet() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _modules);
    newFile(_pagePath, "import '../cart/cart.dart';\nCart? c;\n");
    await assertNoDiagnosticsInFile(_pagePath);
  }

  void test_moduleNotAllowedIsReported() async {
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      '$_modules  allowed:\n    checkout: []\n',
    );
    const code = "import '../cart/cart.dart';\nCart? c;\n";
    newFile(_pagePath, code);
    await assertDiagnosticsInFile(_pagePath, [
      lint(
        code.indexOf("'"),
        "'../cart/cart.dart'".length,
        messageContainsAll: ['may not import other modules'],
      ),
    ]);
  }

  void test_noModulesConfigIsQuiet() async {
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      'forbidden_packages: [dart:mirrors]\n',
    );
    newFile(_pagePath, _privateImport);
    await assertNoDiagnosticsInFile(_pagePath);
  }

  void test_baselineSuppressesKnownViolation() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _modules);
    newFile(
      '$testPackageRootPath/arch_guard_baseline.json',
      jsonEncode({
        'version': 1,
        'cycles': [],
        'moduleViolations': [
          {
            'sourceFile': 'lib/features/checkout/page.dart',
            'targetFile': 'lib/features/cart/data/repo.dart',
          },
        ],
      }),
    );
    newFile(_pagePath, _privateImport);
    await assertNoDiagnosticsInFile(_pagePath);
  }
}

// The test package (`test`, at /home/test) and a `core` member at /home/core
// are members of a workspace whose root /home holds the config.
const _coreImport = "import 'package:core/core.dart';\nCore? c;\n";

@reflectiveTest
class WorkspaceViolationRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = WorkspaceViolationRule();
    // Before super.setUp(), which builds the analysis contexts.
    newFile(
      '$workspaceRootPath/pubspec.yaml',
      'name: root\nworkspace: [test, core]\n',
    );
    newFile('$workspaceRootPath/core/pubspec.yaml', 'name: core\n');
    newFile('$workspaceRootPath/core/lib/core.dart', 'class Core {}\n');
    super.setUp();
    // Map `package:core` to /home/core. Editing the written file, rather
    // than calling the builder API, works with every analyzer_testing
    // version the plugin supports.
    final configPath = '$testPackageRootPath/.dart_tool/package_config.json';
    final config =
        jsonDecode(getFile(configPath).readAsStringSync())
            as Map<String, dynamic>;
    (config['packages'] as List).add({
      'name': 'core',
      'rootUri': toUriStr('$workspaceRootPath/core'),
      'packageUri': 'lib/',
    });
    newFile(configPath, jsonEncode(config));
  }

  String get _appPath => '$testPackageLibPath/app.dart';

  void _rules(String allowed) => newFile(
    '$workspaceRootPath/arch_guard.yaml',
    'workspace_rules:\n  test:\n    allowed: $allowed\n',
  );

  void test_reportsForbiddenMemberImport() async {
    _rules('[]');
    newFile(_appPath, _coreImport);
    await assertDiagnosticsInFile(_appPath, [
      lint(
        _coreImport.indexOf("'"),
        "'package:core/core.dart'".length,
        messageContainsAll: ['`test`', '`core`'],
      ),
    ]);
  }

  void test_allowedMemberIsQuiet() async {
    _rules('[core]');
    newFile(_appPath, _coreImport);
    await assertNoDiagnosticsInFile(_appPath);
  }

  void test_importInsideOneMemberIsQuiet() async {
    _rules('[]');
    newFile('$testPackageLibPath/b.dart', 'class B {}\n');
    newFile(_appPath, "import 'b.dart';\nB? b;\n");
    await assertNoDiagnosticsInFile(_appPath);
  }

  void test_baselineSuppressesKnownViolation() async {
    _rules('[]');
    newFile(
      '$workspaceRootPath/arch_guard_baseline.json',
      jsonEncode({
        'version': 1,
        'cycles': [],
        'workspaceViolations': [
          {
            'sourceFile': 'test/lib/app.dart',
            'targetFile': 'core/lib/core.dart',
          },
        ],
      }),
    );
    newFile(_appPath, _coreImport);
    await assertNoDiagnosticsInFile(_appPath);
  }
}
