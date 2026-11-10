import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  test('own-line comment applies to the next line', () {
    final i = IgnoreComments.parse(
      "// ignore: arch_guard_lint/layer_violation\nimport 'a.dart';\n",
    );
    expect(i.codesAt(2), {'layer_violation'});
    expect(i.codesAt(1), isEmpty);
  });

  test('trailing comment applies to its own line', () {
    final i = IgnoreComments.parse(
      "import 'a.dart'; // ignore: arch_guard_lint/layer_violation\n"
      "import 'b.dart';\n",
    );
    expect(i.codesAt(1), {'layer_violation'});
    expect(i.codesAt(2), isEmpty);
  });

  test('several codes, no spaces, foreign codes dropped', () {
    final i = IgnoreComments.parse(
      '//ignore:arch_guard_lint/layer_violation,unused_import,'
      "arch_guard_lint/forbidden_package\nimport 'a.dart';\n",
    );
    expect(i.codesAt(2), {'layer_violation', 'forbidden_package'});
  });

  test('ignore_for_file applies everywhere', () {
    final i = IgnoreComments.parse(
      '// ignore_for_file: arch_guard_lint/circular_dependency\n\n'
      "import 'a.dart';\n",
    );
    expect(i.forFile, {'circular_dependency'});
    expect(i.codesAt(3), {'circular_dependency'});
    expect(i.codesAt(null), {'circular_dependency'});
  });

  test('text inside a string or block comment is not an ignore', () {
    final i = IgnoreComments.parse(
      "const s = '// ignore: arch_guard_lint/layer_violation';\n"
      "/* // ignore: arch_guard_lint/layer_violation */\nimport 'a.dart';\n",
    );
    expect(i.codesAt(2), isEmpty);
    expect(i.codesAt(3), isEmpty);
  });

  test('multi-line strings and block comments keep line numbers right', () {
    final i = IgnoreComments.parse(
      "/* one\ntwo */\nconst s = '''\nx\n''';\n"
      "// ignore: arch_guard_lint/layer_violation\nimport 'a.dart';\n",
    );
    expect(i.codesAt(7), {'layer_violation'});
  });
}
