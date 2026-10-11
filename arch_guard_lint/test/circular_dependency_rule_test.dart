// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:arch_guard_lint/src/circular_dependency_rule.dart';
import 'package:arch_guard_lint/src/fixes/remove_directive.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CircularDependencyRuleTest);
  });
}

const _a = "import 'b.dart';\nB? b;\nclass A {}\n";
const _b = "import 'a.dart';\nA? a;\nclass B {}\n";

@reflectiveTest
class CircularDependencyRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = CircularDependencyRule();
    CircularDependencyRule.recheckAfter = Duration.zero;
    super.setUp();
  }

  String get _aPath => '$testPackageLibPath/a.dart';
  String get _bPath => '$testPackageLibPath/b.dart';

  void test_reportsTheImportThatBreaksTheCycle() async {
    newFile(_aPath, _a);
    newFile(_bPath, _b);
    // CycleBreaker picks lib/a.dart -> lib/b.dart (first in sorted order).
    await assertDiagnosticsInFile(_aPath, [
      lint(
        7,
        "'b.dart'".length,
        messageContainsAll: ['lib/a.dart -> lib/b.dart', 'breaks the cycle'],
      ),
    ]);
    await assertNoDiagnosticsInFile(_bPath);
  }

  void test_noCycleIsQuiet() async {
    newFile(_aPath, "import 'b.dart';\nB? b;\n");
    newFile(_bPath, 'class B {}\n');
    await assertNoDiagnosticsInFile(_aPath);
  }

  void test_noConfigNeeded_butBaselineCycleIsQuiet() async {
    newFile(
      '$testPackageRootPath/arch_guard_baseline.json',
      jsonEncode({
        'version': 1,
        'cycles': [
          {
            'files': ['lib/a.dart', 'lib/b.dart'],
          },
        ],
        'layerViolations': [],
      }),
    );
    newFile(_aPath, _a);
    newFile(_bPath, _b);
    await assertNoDiagnosticsInFile(_aPath);
  }

  void test_breakingTheCycleClearsTheWarning() async {
    newFile(_aPath, _a);
    newFile(_bPath, _b);
    await assertDiagnosticsInFile(_aPath, [lint(7, "'b.dart'".length)]);
    newFile(_bPath, 'class B {}\n'); // cycle gone
    newFile(_aPath, '$_a// edited\n');
    await assertNoDiagnosticsInFile(_aPath);
  }

  void test_generatedFilesDoNotCount() async {
    newFile(_aPath, "import 'a.g.dart';\nG? g;\nclass A {}\n");
    newFile(
      '$testPackageLibPath/a.g.dart',
      "import 'a.dart';\nA? a;\nclass G {}\n",
    );
    await assertNoDiagnosticsInFile(_aPath);
  }

  void test_configIgnoreIsHonoured() async {
    newFile('$testPackageRootPath/arch_guard.yaml', 'ignore: ["lib/b.dart"]\n');
    newFile(_aPath, _a);
    newFile(_bPath, _b);
    await assertNoDiagnosticsInFile(_aPath);
  }

  void test_removeFixDeletesTheImport() async {
    newFile(_aPath, "import 'b.dart';\nclass A {}\n");
    newFile(_bPath, _b);
    final (out, _) = await applyFix(this, _aPath, RemoveDirective.new);
    expect(out[convertPath(_aPath)], 'class A {}\n');
  }

  void test_docCommentAboveTheImport() async {
    const code = "/// Docs.\nimport 'b.dart';\nB? b;\nclass A {}\n";
    newFile(_aPath, code);
    newFile(_bPath, _b);
    await assertDiagnosticsInFile(_aPath, [
      lint(code.indexOf("'b.dart'"), "'b.dart'".length),
    ]);
  }

  void test_cycleThroughAConditionalClause() async {
    newFile('$testPackageLibPath/stub.dart', 'class B {}\n');
    const code =
        "import 'stub.dart' if (dart.library.nope) 'b.dart';\n"
        'B? b;\nclass A {}\n';
    newFile(_aPath, code);
    newFile(_bPath, _b);
    await assertDiagnosticsInFile(_aPath, [
      lint(code.indexOf("'b.dart'"), "'b.dart'".length),
    ]);
  }

  void test_editInTheCycleIsSeenInsideTheRecheckWindow() async {
    CircularDependencyRule.recheckAfter = const Duration(hours: 1);
    newFile(_aPath, _a);
    newFile(_bPath, _b);
    await assertDiagnosticsInFile(_aPath, [lint(7, "'b.dart'".length)]);
    newFile(_bPath, 'class B {}\n'); // cycle gone
    newFile(_aPath, '$_a// edited\n');
    await assertNoDiagnosticsInFile(_aPath);
  }

  void test_brokenPubspecStillWorks() async {
    newFile('$testPackageRootPath/pubspec.yaml', 'name: test\nversion: [');
    newFile(_aPath, _a);
    newFile(_bPath, _b);
    await assertDiagnosticsInFile(_aPath, [lint(7, "'b.dart'".length)]);
  }
}
