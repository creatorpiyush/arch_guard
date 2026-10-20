// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:arch_guard_lint/src/layer_violation_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(LayerViolationRuleTest);
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

// Each source uses what it imports, so no `unused_import` warning shows up.
const _badImport = "import '../data/repo.dart';\nRepo? r;\n";

@reflectiveTest
class LayerViolationRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = LayerViolationRule();
    super.setUp();
    newFile('$testPackageLibPath/data/repo.dart', 'class Repo {}\n');
    newFile('$testPackageLibPath/domain/user.dart', 'class User {}\n');
  }

  String get _userPath => '$testPackageLibPath/domain/user_view.dart';

  void test_reportsForbiddenLayerImport() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile(_userPath, _badImport);
    await assertDiagnosticsInFile(_userPath, [
      lint(
        _badImport.indexOf("'"),
        "'../data/repo.dart'".length,
        messageContainsAll: ['`domain`', '`data`'],
      ),
    ]);
  }

  void test_packageUriToOwnPackageIsChecked() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    const code = "import 'package:test/data/repo.dart';\nRepo? r;\n";
    newFile(_userPath, code);
    await assertDiagnosticsInFile(_userPath, [
      lint(code.indexOf("'"), "'package:test/data/repo.dart'".length),
    ]);
  }

  void test_allowedImportIsQuiet() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    final path = '$testPackageLibPath/data/repo_impl.dart';
    newFile(path, "import '../domain/user.dart';\nUser? u;\n");
    await assertNoDiagnosticsInFile(path);
  }

  void test_noConfigIsQuiet() async {
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_brokenConfigIsQuiet() async {
    newFile('$testPackageRootPath/arch_guard.yaml', 'layers: [:::');
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_baselineSuppressesKnownViolation() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile(
      '$testPackageRootPath/arch_guard_baseline.json',
      jsonEncode({
        'version': 1,
        'cycles': [],
        'layerViolations': [
          {
            'sourceFile': 'lib/domain/user_view.dart',
            'targetFile': 'lib/data/repo.dart',
          },
        ],
      }),
    );
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_brokenBaselineIsIgnored() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile('$testPackageRootPath/arch_guard_baseline.json', '{nope');
    newFile(_userPath, _badImport);
    await assertDiagnosticsInFile(_userPath, [
      lint(_badImport.indexOf("'"), "'../data/repo.dart'".length),
    ]);
  }

  void test_ignoredFilesAreQuiet() async {
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      '$_config\nignore: ["lib/domain/user_view.dart"]\n',
    );
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_invalidGlobIsQuiet() async {
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      '$_config\nforbidden_packages: ["x["]\nignore: ["lib/[x"]\n',
    );
    newFile(_userPath, _badImport);
    // Invalid entries are dropped; the valid layer rules still apply.
    await assertDiagnosticsInFile(_userPath, [
      lint(_badImport.indexOf("'"), "'../data/repo.dart'".length),
    ]);
  }

  void test_importOfIgnoredFileIsQuiet() async {
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      '$_config\nignore: ["lib/data/**"]\n',
    );
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_generatedFilesAreQuiet() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    final path = '$testPackageLibPath/domain/user.g.dart';
    newFile(path, _badImport);
    await assertNoDiagnosticsInFile(path);
  }

  void test_configAboveANonWorkspaceRootIsNotUsed() async {
    newFile('$workspaceRootPath/arch_guard.yaml', _config);
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_configAtTheWorkspaceRootIsUsed() async {
    newFile(
      '$workspaceRootPath/pubspec.yaml',
      'name: root\nworkspace: [test]\n',
    );
    newFile('$workspaceRootPath/arch_guard.yaml', _config);
    newFile(_userPath, _badImport);
    await assertDiagnosticsInFile(_userPath, [
      lint(_badImport.indexOf("'"), "'../data/repo.dart'".length),
    ]);
  }

  void test_partInAnotherLayerIsChecked() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile(
      '$testPackageLibPath/data/user_view_part.dart',
      "part of '../domain/user_view.dart';\n",
    );
    const code = "part '../data/user_view_part.dart';\n";
    newFile(_userPath, code);
    await assertDiagnosticsInFile(_userPath, [
      lint(code.indexOf("'"), "'../data/user_view_part.dart'".length),
    ]);
  }

  void test_barrelInNoLayerIsFollowed() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile('$testPackageLibPath/exports.dart', "export 'data/repo.dart';\n");
    const code = "import '../exports.dart';\nRepo? r;\n";
    newFile(_userPath, code);
    await assertDiagnosticsInFile(_userPath, [
      lint(
        code.indexOf("'"),
        "'../exports.dart'".length,
        messageContainsAll: ['`lib/data/repo.dart`', 'via lib/exports.dart'],
      ),
    ]);
  }

  void test_barrelThatOnlyImportsIsQuiet() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile(
      '$testPackageLibPath/exports.dart',
      "import 'data/repo.dart';\nclass E {}\nRepo? r;\n",
    );
    const code = "import '../exports.dart';\nE? e;\n";
    newFile(_userPath, code);
    await assertNoDiagnosticsInFile(_userPath);
  }

  void test_conditionalImportIsChecked() async {
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    // The configured URI is checked even when the condition is false.
    const code =
        "import 'user.dart' if (dart.library.nope) '../data/repo.dart';\n"
        'User? u;\n';
    newFile(_userPath, code);
    await assertDiagnosticsInFile(_userPath, [
      lint(code.indexOf("'../data"), "'../data/repo.dart'".length),
    ]);
  }

  void test_legacyConfigChangeIsPickedUp() async {
    newFile('$testPackageRootPath/dep_graph.yaml', 'layers: {}\n');
    newFile(_userPath, _badImport);
    await assertNoDiagnosticsInFile(_userPath);

    // Like an editor saving the file: a new content and modification stamp.
    resourceProvider
        .getFile(convertPath('$testPackageRootPath/dep_graph.yaml'))
        .writeAsStringSync(_config);
    newFile(_userPath, '$_badImport// edited\n');
    await assertDiagnosticsInFile(_userPath, [
      lint(_badImport.indexOf("'"), "'../data/repo.dart'".length),
    ]);
  }
}
