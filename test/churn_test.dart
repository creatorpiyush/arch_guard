import 'dart:convert';
import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  ProcessResult run(List<String> args, {String? date}) => Process.runSync(
    'git',
    args,
    workingDirectory: dir.path,
    environment: date == null
        ? null
        : {'GIT_AUTHOR_DATE': date, 'GIT_COMMITTER_DATE': date},
  );

  void git(List<String> args, {String? date}) {
    final r = run(args, date: date);
    if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
  }

  void write(String path, String content) {
    final f = File(p.join(dir.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  /// hub is imported by a, b and c (coupling 3); a also imports b.
  void project(String metrics) {
    dir = Directory.systemTemp.createTempSync('arch_guard_churn_');
    write('pubspec.yaml', 'name: app\n');
    write('arch_guard.yaml', 'metrics:\n$metrics');
    write('lib/hub.dart', '');
    write('lib/a.dart', "import 'hub.dart';\nimport 'b.dart';\n");
    write('lib/b.dart', "import 'hub.dart';\n");
    write('lib/c.dart', "import 'hub.dart';\n");
  }

  void initGit({String? date}) {
    git(['init', '-q', '-b', 'main']);
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);
    git(['add', '.']);
    git(['commit', '-qm', 'base'], date: date);
  }

  void touchC(int times) {
    for (var i = 0; i < times; i++) {
      write('lib/c.dart', "import 'hub.dart';\n// $i\n");
      git(['commit', '-qam', 'c $i']);
    }
  }

  tearDown(() => dir.deleteSync(recursive: true));

  Future<ArchAnalysis> analyse() => ArchAnalysis.run(projectPath: dir.path);

  test('ranks by commits times coupling', () async {
    project('  churn_since: "10 years ago"\n  hotspots: 2\n');
    initGit();
    touchC(4);
    final a = await analyse();
    // hub: 1 commit x 3 = 3; c: 5 commits x 1 = 5.
    expect(a.churn!['lib/c.dart'], 5);
    expect(a.hotspots.map((m) => m.file), ['lib/c.dart', 'lib/hub.dart']);
  });

  test('untouched files drop out', () async {
    project('  churn_since: "2020-01-01"\n');
    initGit(date: '2000-01-01T00:00:00');
    touchC(1);
    final a = await analyse();
    expect(a.churn, {'lib/c.dart': 1});
    expect(a.hotspots.map((m) => m.file), ['lib/c.dart']);
  });

  test('not a git repository: warning and coupling ranking', () async {
    project('  churn_since: "6 months ago"\n');
    final a = await analyse();
    expect(a.churn, isNull);
    expect(a.warnings, contains(startsWith('metrics: churn_since ignored: ')));
    expect(a.hotspots.first.file, 'lib/hub.dart');
  });

  test('no commits in the window: warning and coupling ranking', () async {
    project('  churn_since: "2020-01-01"\n');
    initGit(date: '2000-01-01T00:00:00');
    final a = await analyse();
    expect(a.churn, isNull);
    expect(
      a.warnings,
      contains(
        'metrics: churn_since: no commits since "2020-01-01". Hotspots are '
        'ranked by coupling only.',
      ),
    );
    expect(a.hotspots.first.file, 'lib/hub.dart');
  });

  test('failures are unchanged', () async {
    project('  churn_since: "10 years ago"\n  max_fan_in: 2\n');
    initGit();
    touchC(2);
    final withChurn = (await analyse()).failures();
    write('arch_guard.yaml', 'metrics:\n  max_fan_in: 2\n');
    expect(withChurn, (await analyse()).failures());
  });

  test('CLI: --json hotspots carry commits', () async {
    project('  churn_since: "10 years ago"\n');
    initGit();
    touchC(1);
    final r = await Process.run(Platform.resolvedExecutable, [
      'bin/arch_guard.dart',
      dir.path,
      '--json',
    ]);
    final data = jsonDecode(r.stdout as String) as Map;
    expect(data['churnSince'], '10 years ago');
    final hot = {
      for (final h in data['hotspots'] as List) h['file']: h['commits'],
    };
    expect(hot['lib/hub.dart'], 1);
    expect(hot['lib/c.dart'], 2);
  });

  test('CLI: terminal hotspot lines carry commits', () async {
    project('  churn_since: "10 years ago"\n');
    initGit();
    touchC(1);
    final r = await Process.run(Platform.resolvedExecutable, [
      'bin/arch_guard.dart',
      dir.path,
      '--no-color',
    ]);
    expect(r.stdout, contains('lib/c.dart  in 0  out 1  commits 2'));
  });
}
