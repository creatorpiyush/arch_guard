import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory repo;

  void git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: repo.path);
    if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
  }

  void write(String path, String content) {
    final f = File(p.join(repo.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  int worktrees() {
    final r = Process.runSync('git', [
      'worktree',
      'list',
      '--porcelain',
    ], workingDirectory: repo.path);
    return (r.stdout as String)
        .split('\n')
        .where((l) => l.startsWith('worktree '))
        .length;
  }

  void initRepo(Map<String, String> files) {
    repo = Directory.systemTemp.createTempSync('arch_guard_diff_');
    git(['init', '-q', '-b', 'main']);
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);
    files.forEach(write);
    git(['add', '.']);
    git(['commit', '-qm', 'base']);
    git(['checkout', '-qb', 'feature']);
  }

  tearDown(() => repo.deleteSync(recursive: true));

  const importB = "import 'package:app/data/b.dart';\n";

  group('layers', () {
    setUp(
      () => initRepo({
        'pubspec.yaml': 'name: app\n',
        'arch_guard.yaml': '''
layers:
  presentation:
    patterns: ["lib/ui/**"]
  data:
    patterns: ["lib/data/**"]
''',
        '.gitignore': '*.config.dart\n',
        'lib/ui/a.dart': '',
        'lib/data/b.dart': '',
      }),
    );

    Future<ArchAnalysis> run({String? since = 'main', bool diff = true}) =>
        ArchAnalysis.run(projectPath: repo.path, since: since, graphDiff: diff);

    test('reports a new layer edge', () async {
      write('lib/ui/a.dart', importB);
      git(['commit', '-qam', 'import']);
      final d = (await run()).graphDiff!;
      expect(d.groupEdges.single.from, 'presentation');
      expect(d.groupEdges.single.to, 'data');
      expect(d.base, hasLength(40));
    });

    test('uncommitted change counts', () async {
      write('lib/ui/a.dart', importB);
      expect((await run()).graphDiff!.groupEdges.single.to, 'data');
    });

    test('ignored generated file adds nothing', () async {
      write('lib/ui/di.config.dart', importB);
      final analysis = await run();
      expect(analysis.scan.files, contains('lib/ui/di.config.dart'));
      expect(analysis.graphDiff!.isEmpty, isTrue);
    });

    test('off by default and without since', () async {
      write('lib/ui/a.dart', importB);
      expect(
        (await ArchAnalysis.run(
          projectPath: repo.path,
          since: 'main',
        )).graphDiff,
        isNull,
      );
      expect((await run(since: null)).graphDiff, isNull);
    });

    test('failures are unchanged', () async {
      write('lib/ui/a.dart', importB);
      expect((await run()).failures(), (await run(diff: false)).failures());
    });

    test('no worktree left', () async {
      write('lib/ui/a.dart', importB);
      await run();
      expect(worktrees(), 1);
    });
  });

  test('workspace member dependency', () async {
    initRepo({
      'pubspec.yaml':
          'name: root\nworkspace:\n  - packages/a\n  - packages/b\n',
      'packages/a/pubspec.yaml': 'name: a\nresolution: workspace\n',
      'packages/b/pubspec.yaml': 'name: b\nresolution: workspace\n',
      'packages/a/lib/a.dart': '',
      'packages/b/lib/b.dart': '',
    });
    write('packages/a/lib/a.dart', "import 'package:b/b.dart';\n");
    git(['commit', '-qam', 'use b']);
    final d = (await ArchAnalysis.run(
      projectPath: repo.path,
      since: 'main',
      graphDiff: true,
    )).graphDiff!;
    expect(d.groupEdges.map((e) => '${e.kind} ${e.from} ${e.to}'), [
      'member a b',
    ]);
  });
}
