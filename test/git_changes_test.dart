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

  setUp(() {
    repo = Directory.systemTemp.createTempSync('arch_guard_git_');
    git(['init', '-q', '-b', 'main']);
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);
    git(['config', 'core.quotepath', 'true']);
    write('app/lib/a.dart', '');
    write('app/lib/b.dart', '');
    write('other/x.dart', '');
    git(['add', '.']);
    git(['commit', '-qm', 'base']);
    git(['checkout', '-qb', 'feature']);
    write('app/lib/a.dart', '// committed change');
    write('other/x.dart', '// outside the project');
    git(['commit', '-qam', 'change']);
    write('app/lib/b.dart', '// uncommitted');
    write('app/lib/new file é.dart', ''); // untracked, space + unicode
  });

  tearDown(() => repo.deleteSync(recursive: true));

  test('committed, uncommitted and untracked, relative to the project', () {
    final changed = GitChanges.since(
      'main',
      projectRoot: p.join(repo.path, 'app'),
    );
    expect(changed, {'lib/a.dart', 'lib/b.dart', 'lib/new file é.dart'});
  });

  test('unknown ref and non-repo directories throw GitException', () {
    expect(
      () => GitChanges.since('nope', projectRoot: repo.path),
      throwsA(isA<GitException>()),
    );
    final plain = Directory.systemTemp.createTempSync('arch_guard_nogit_');
    addTearDown(() => plain.deleteSync(recursive: true));
    expect(
      () => GitChanges.since('main', projectRoot: plain.path),
      throwsA(
        isA<GitException>().having(
          (e) => e.message,
          'message',
          contains('git'),
        ),
      ),
    );
  });

  test('rejects refs that git would read as options', () {
    expect(
      () => GitChanges.since('--output=x', projectRoot: repo.path),
      throwsA(isA<GitException>()),
    );
    expect(File(p.join(repo.path, 'x')).existsSync(), isFalse);
  });

  test('git errors are one line', () {
    expect(
      () => GitChanges.since('nope', projectRoot: repo.path),
      throwsA(
        isA<GitException>().having(
          (e) => e.message,
          'message',
          isNot(contains('\n')),
        ),
      ),
    );
  });

  test('a ref that is also a path name', () {
    git(['branch', 'app', 'main']);
    expect(GitChanges.since('app', projectRoot: repo.path), {
      'app/lib/a.dart',
      'app/lib/b.dart',
      'app/lib/new file é.dart',
      'other/x.dart',
    });
  });

  test('ignores diff.relative in the user config', () {
    git(['config', 'diff.relative', 'true']);
    expect(GitChanges.since('main', projectRoot: p.join(repo.path, 'app')), {
      'lib/a.dart',
      'lib/b.dart',
      'lib/new file é.dart',
    });
  });

  test('missing merge base explains how to fix shallow clones', () {
    expect(
      () => GitChanges.since('nope', projectRoot: repo.path),
      throwsA(
        isA<GitException>().having(
          (e) => e.message,
          'message',
          contains('fetch-depth: 0'),
        ),
      ),
    );
  });

  test('old git without --merge-base gets a version hint', () {
    expect(
      GitChanges.errorMessage(
        'error: invalid option: --merge-base',
        command: 'diff',
        ref: 'main',
      ),
      contains('git 2.30'),
    );
    // git < 2.28 rejects --no-relative before it reaches --merge-base.
    expect(
      GitChanges.errorMessage(
        "error: unknown option `no-relative'",
        command: 'diff',
        ref: 'main',
      ),
      contains('git 2.30'),
    );
    expect(
      GitChanges.errorMessage('fatal: bad revision', command: 'diff', ref: 'x'),
      contains('fetch-depth: 0'),
    );
    // A ref whose name mentions the words is still a missing ref.
    expect(
      GitChanges.errorMessage(
        "fatal: bad revision 'fix/unrecognized-merge-base'",
        command: 'diff',
        ref: 'fix/unrecognized-merge-base',
      ),
      contains('fetch-depth: 0'),
    );
  });

  group('base checkout', () {
    String app() => p.join(repo.path, 'app');
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

    test('mergeBase returns the main commit', () {
      final main = Process.runSync('git', [
        'rev-parse',
        'main',
      ], workingDirectory: repo.path);
      expect(
        GitChanges.mergeBase('main', projectRoot: app()),
        (main.stdout as String).trim(),
      );
    });

    test('mergeBase rejects refs that git would read as options', () {
      expect(
        () => GitChanges.mergeBase('--foo', projectRoot: app()),
        throwsA(isA<GitException>()),
      );
    });

    test('knownFiles skips ignored files', () {
      write('.gitignore', '*.config.dart\n');
      write('app/lib/di.config.dart', '');
      write('app/lib/new.dart', '');
      final known = GitChanges.knownFiles(projectRoot: app());
      expect(known, containsAll(['lib/new.dart', 'lib/a.dart']));
      expect(known, isNot(contains('lib/di.config.dart')));
      expect(known.where((f) => f.contains('x.dart')), isEmpty);
    });

    test(
      'withBaseCheckout sees base content in a sub-folder project',
      () async {
        final content = await GitChanges.withBaseCheckout(
          GitChanges.mergeBase('main', projectRoot: app()),
          projectRoot: app(),
          body: (baseRoot) async {
            expect(p.basename(baseRoot), 'app');
            return File(p.join(baseRoot, 'lib', 'a.dart')).readAsStringSync();
          },
        );
        expect(content, '');
      },
    );

    test('withBaseCheckout cleans up', () async {
      late String baseRoot;
      await GitChanges.withBaseCheckout(
        GitChanges.mergeBase('main', projectRoot: app()),
        projectRoot: app(),
        body: (root) async => baseRoot = root,
      );
      expect(Directory(baseRoot).existsSync(), isFalse);
      expect(worktrees(), 1);
    });

    test('withBaseCheckout cleans up when body throws', () async {
      late String baseRoot;
      await expectLater(
        GitChanges.withBaseCheckout(
          GitChanges.mergeBase('main', projectRoot: app()),
          projectRoot: app(),
          body: (root) async {
            baseRoot = root;
            throw StateError('boom');
          },
        ),
        throwsStateError,
      );
      expect(Directory(baseRoot).existsSync(), isFalse);
      expect(worktrees(), 1);
    });

    test('withBaseCheckout rejects an unknown sha', () async {
      await expectLater(
        GitChanges.withBaseCheckout(
          '0' * 40,
          projectRoot: app(),
          body: (_) async => null,
        ),
        throwsA(isA<GitException>()),
      );
      expect(worktrees(), 1);
    });
  });
}
