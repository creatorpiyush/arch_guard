// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:arch_guard_lint/src/fixes/remove_directive.dart';
import 'package:arch_guard_lint/src/forbidden_package_rule.dart';
import 'package:arch_guard_lint/src/layer_violation_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RemoveLayerImportTest);
    defineReflectiveTests(RemoveForbiddenImportTest);
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
class RemoveLayerImportTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = LayerViolationRule();
    super.setUp();
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
    newFile('$testPackageLibPath/data/repo.dart', 'class Repo {}\n');
    newFile('$testPackageLibPath/domain/user.dart', 'class User {}\n');
  }

  String get _path => '$testPackageLibPath/domain/user_view.dart';

  void test_removesTheImport() async {
    newFile(
      _path,
      "import '../data/repo.dart';\nimport 'user.dart';\nRepo? r;\nUser? u;\n",
    );
    final (out, message) = await applyFix(this, _path, RemoveDirective.new);
    expect(
      out[convertPath(_path)],
      "import 'user.dart';\nRepo? r;\nUser? u;\n",
    );
    expect(message, 'Remove this import');
  }

  void test_removesOnlyTheConditionalClause() async {
    newFile(
      _path,
      "import 'user.dart' if (dart.library.nope) '../data/repo.dart';\n"
      'User? u;\n',
    );
    final (out, _) = await applyFix(this, _path, RemoveDirective.new);
    expect(out[convertPath(_path)], "import 'user.dart';\nUser? u;\n");
  }

  void test_removesAnExport() async {
    newFile(_path, "export '../data/repo.dart';\n");
    final (out, message) = await applyFix(this, _path, RemoveDirective.new);
    expect(out[convertPath(_path)], '');
    expect(message, 'Remove this export');
  }
}

@reflectiveTest
class RemoveForbiddenImportTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ForbiddenPackageRule();
    super.setUp();
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      'forbidden_packages: ["dart:io"]\n',
    );
  }

  void test_removesTheImport() async {
    final path = '$testPackageLibPath/a.dart';
    newFile(path, "import 'dart:io';\n\nFile? f;\n");
    final (out, _) = await applyFix(this, path, RemoveDirective.new);
    expect(out[convertPath(path)], '\nFile? f;\n');
  }
}
