import 'dart:io';

import 'package:test/test.dart';

ProcessResult _run(List<String> args) => Process.runSync(
  Platform.resolvedExecutable,
  ['bin/arch_guard.dart', ...args],
);

ProcessResult _why(List<String> args) =>
    _run(['why', ...args, 'example/cases/sample_project', '--no-color']);

void main() {
  test('prints the path', () {
    final r = _why(['lib/main.dart', 'dart:convert']);
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(
      r.stdout,
      'lib/main.dart reaches dart:convert in 3 step(s):\n'
      '  lib/main.dart:2  import  lib/services/auth_service.dart\n'
      '  lib/services/auth_service.dart:1  import  lib/models/user.dart\n'
      '  lib/models/user.dart:2  import  dart:convert\n',
    );
  });

  test('from inside the target', () {
    final r = _why(['lib/main.dart', 'lib']);
    expect(r.exitCode, 0);
    expect(r.stdout, 'lib/main.dart is in lib/.\n');
  });

  test('no path exits 1', () {
    final r = _why([r'lib\widgets', 'lib/services']);
    expect(r.exitCode, 1);
    expect(r.stdout, 'No import path from lib/widgets to lib/services/.\n');
  });

  test('bad arguments exit 64', () {
    var r = _why(['lib/nope.dart', 'lib/main.dart']);
    expect(r.exitCode, 64);
    expect(
      r.stderr,
      contains('Error: no scanned file or folder matches "lib/nope.dart".'),
    );

    r = _run(['why', 'lib/main.dart']);
    expect(r.exitCode, 64);

    r = _run(['--watch', 'why', 'lib/main.dart', 'lib/models/user.dart']);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('--watch cannot be combined with why'));
  });
}
