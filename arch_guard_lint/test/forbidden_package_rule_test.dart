// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:arch_guard_lint/src/forbidden_package_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ForbiddenPackageRuleTest);
  });
}

const _config = '''
forbidden_packages: ["dart:mirrors", http]
layers:
  domain:
    patterns: ["lib/domain/**"]
    forbidden_packages: [flutter, "dart:io"]
  data:
    patterns: ["lib/data/**"]
''';

@reflectiveTest
class ForbiddenPackageRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ForbiddenPackageRule();
    newPackage('flutter').addFile('lib/widgets.dart', 'class Widget {}\n');
    // The test SDK has no dart:mirrors, so the project-wide case uses a stub.
    newPackage('http').addFile('lib/http.dart', 'class Client {}\n');
    super.setUp();
    newFile('$testPackageRootPath/arch_guard.yaml', _config);
  }

  void test_layerForbidsPackage() async {
    const code = "import 'package:flutter/widgets.dart';\nWidget? w;\n";
    final path = '$testPackageLibPath/domain/a.dart';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [
      lint(
        code.indexOf("'"),
        "'package:flutter/widgets.dart'".length,
        messageContainsAll: ['`domain`', '`flutter`'],
      ),
    ]);
  }

  void test_otherLayerMayUseIt() async {
    final path = '$testPackageLibPath/data/a.dart';
    newFile(path, "import 'package:flutter/widgets.dart';\nWidget? w;\n");
    await assertNoDiagnosticsInFile(path);
  }

  void test_dartLibrary() async {
    const code = "import 'dart:io';\nFile? f;\n";
    final path = '$testPackageLibPath/domain/a.dart';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [
      lint(code.indexOf("'"), "'dart:io'".length),
    ]);
  }

  void test_projectWideRuleOutsideLayers() async {
    const code = "import 'package:http/http.dart';\nClient? c;\n";
    final path = '$testPackageLibPath/main.dart';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [
      lint(code.indexOf("'"), "'package:http/http.dart'".length),
    ]);
  }

  void test_conditionalImportUrisAreChecked() async {
    newFile('$testPackageLibPath/domain/stub.dart', 'class Widget {}\n');
    const code =
        "import 'stub.dart' if (dart.library.ui) 'package:flutter/widgets.dart';\n"
        'Widget? w;\n';
    final path = '$testPackageLibPath/domain/a.dart';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [
      lint(
        code.indexOf("'package:flutter"),
        "'package:flutter/widgets.dart'".length,
      ),
    ]);
  }

  void test_ownPackageIsNeverForbidden() async {
    newFile(
      '$testPackageRootPath/arch_guard.yaml',
      'forbidden_packages: [test]\n',
    );
    newFile('$testPackageLibPath/x.dart', 'class X {}\n');
    final path = '$testPackageLibPath/a.dart';
    newFile(path, "import 'package:test/x.dart';\nX? x;\n");
    await assertNoDiagnosticsInFile(path);
  }
}
