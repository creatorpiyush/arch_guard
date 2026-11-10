import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  void git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: project.path);
    if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
  }

  void write(String path, String content) {
    final f = File(p.join(project.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  ProcessResult affected(List<String> args) => Process.runSync(
    Platform.resolvedExecutable,
    ['bin/arch_guard.dart', 'affected', project.path, ...args],
  );

  setUp(() {
    project = Directory.systemTemp.createTempSync('arch_guard_affected_');
    write('pubspec.yaml', 'name: app\n');
    write('lib/a.dart', '');
    write('lib/b.dart', "import 'a.dart';\n");
    write('test/b_test.dart', "import 'package:app/b.dart';\n");
    write('test/other_test.dart', '');
    git(['init', '-q', '-b', 'main']);
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);
    git(['add', '.']);
    git(['commit', '-qm', 'base']);
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('prints affected tests, files, packages and JSON', () {
    write('lib/a.dart', '// changed\n');
    write('assets/logo.png', 'x');

    var r = affected(['--since', 'main']);
    expect(r.exitCode, 0, reason: r.stderr as String);
    expect(r.stdout, 'test/b_test.dart\n');
    expect(
      r.stderr,
      contains('Note: 1 changed non-Dart file(s) ignored: assets/logo.png'),
    );

    r = affected(['--since', 'main', '--print', 'files']);
    expect(r.stdout, 'lib/a.dart\nlib/b.dart\ntest/b_test.dart\n');

    r = affected(['--since', 'main', '--print', 'packages']);
    expect(r.stdout, 'app\n');

    r = affected(['--since', 'main', '--json']);
    final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(json.keys, [
      'since',
      'changedFiles',
      'files',
      'tests',
      'packages',
      'ignoredChanges',
    ]);
    expect(json['since'], 'main');
    expect(json['changedFiles'], ['assets/logo.png', 'lib/a.dart']);
    expect(json['tests'], ['test/b_test.dart']);
    expect(json['packages'], [
      {'name': 'app', 'path': '.'},
    ]);
    expect(json['ignoredChanges'], ['assets/logo.png']);
  });

  test('renamed file lists tests importing the old path', () {
    git(['checkout', '-qb', 'feature']);
    git(['mv', 'lib/b.dart', 'lib/c.dart']);
    git(['commit', '-qm', 'rename']);
    final r = affected(['--since', 'main']);
    expect(r.stdout, 'test/b_test.dart\n');
  });

  test('no affected tests prints nothing to stdout', () {
    write('lib/lonely.dart', '');
    final r = affected(['--since', 'main']);
    expect(r.exitCode, 0);
    expect(r.stdout, '');
    expect(r.stderr, contains('No affected tests.'));
  });

  test('missing --since, bad ref and --watch are rejected', () {
    var r = affected([]);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('--since'));

    r = affected(['--since', 'no-such-ref']);
    expect(r.exitCode, 2);
    expect(r.stderr, contains('Error:'));

    r = Process.runSync(Platform.resolvedExecutable, [
      'bin/arch_guard.dart',
      '--watch',
      'affected',
      '--since',
      'main',
    ]);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('--watch cannot be combined with affected'));
  });
}
