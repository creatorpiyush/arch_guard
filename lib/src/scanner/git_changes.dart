import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A git command needed by `--since` failed.
class GitException implements Exception {
  /// What went wrong, ready to print.
  final String message;

  /// Creates the exception.
  const GitException(this.message);

  @override
  String toString() => message;
}

/// Files changed in git, for `--since`.
class GitChanges {
  /// Project-relative, `/`-separated paths changed since the merge base of
  /// [ref] and HEAD, plus uncommitted and untracked files. Files outside
  /// [projectRoot] are left out. Throws [GitException] when git fails.
  static Set<String> since(String ref, {required String projectRoot}) {
    _checkRef(ref);
    // Resolve symlinks on both sides: git prints the real path (macOS
    // temp dirs live under /private/var, reached via /var).
    final root = _real(projectRoot);
    final top = _real(_git(['rev-parse', '--show-toplevel'], root).trim());
    final repoPaths = [
      ..._nulSplit(
        _git(
          [
            'diff',
            // Ignore user config that changes the output format.
            '--no-relative',
            '--no-ext-diff',
            '--no-color',
            '--name-only',
            // List both sides of a rename: files still importing the old
            // path are affected.
            '--no-renames',
            '-z',
            '--merge-base',
            ref,
            '--',
          ],
          root,
          ref: ref,
        ),
      ),
      ..._nulSplit(
        _git([
          'ls-files',
          '--others',
          '--exclude-standard',
          '--full-name',
          '-z',
        ], root),
      ),
    ];
    return _projectPaths(repoPaths, root: root, top: top);
  }

  /// The full sha of the merge base of [ref] and HEAD. Throws [GitException]
  /// when git fails.
  static String mergeBase(String ref, {required String projectRoot}) {
    _checkRef(ref);
    return _git(
      ['merge-base', ref, 'HEAD'],
      _real(projectRoot),
      ref: ref,
    ).trim();
  }

  /// Project-relative, `/`-separated paths of the files git knows under
  /// [projectRoot]: tracked, plus untracked files that are not ignored.
  /// Throws [GitException] when git fails.
  static Set<String> knownFiles({required String projectRoot}) {
    final root = _real(projectRoot);
    final top = _real(_git(['rev-parse', '--show-toplevel'], root).trim());
    return _projectPaths(
      _nulSplit(
        _git([
          'ls-files',
          '--cached',
          '--others',
          '--exclude-standard',
          '--full-name',
          '-z',
        ], root),
      ),
      root: root,
      top: top,
    );
  }

  /// Checks out commit [sha] in a temporary git worktree, calls [body] with
  /// the path of [projectRoot] inside it, and removes the worktree
  /// afterwards, also when [body] throws. Throws [GitException] when the
  /// checkout fails.
  static Future<T> withBaseCheckout<T>(
    String sha, {
    required String projectRoot,
    required Future<T> Function(String baseProjectRoot) body,
  }) async {
    final root = _real(projectRoot);
    final top = _real(_git(['rev-parse', '--show-toplevel'], root).trim());
    final tmp = Directory.systemTemp.createTempSync('arch_guard_base_');
    final checkout = p.join(tmp.path, 'base');
    try {
      _git(
        [
          // Not the repo's hooks: a post-checkout `pub get` would run (or
          // fail) on every report. The folder does not exist.
          '-c',
          'core.hooksPath=${p.join(tmp.path, 'no-hooks')}',
          'worktree',
          'add',
          '--detach',
          '--quiet',
          checkout,
          sha,
        ],
        root,
        // Only Dart sources are read: skip Git LFS downloads.
        environment: const {'GIT_LFS_SKIP_SMUDGE': '1'},
      );
      return await body(p.join(checkout, p.relative(root, from: top)));
    } finally {
      try {
        _git(['worktree', 'remove', '--force', checkout], root);
      } on GitException {
        // Deleting the folder below leaves a stale entry; prune drops it.
      }
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // A temp folder left behind must not hide the real result.
      }
      try {
        _git(['worktree', 'prune'], root);
      } on GitException {
        // Same: cleanup never masks the result.
      }
    }
  }

  /// Commits per file since [since] (a git date such as `6 months ago`),
  /// for project files under [projectRoot], keyed by project-relative `/`
  /// path. Merge commits are skipped. A renamed file's earlier commits count
  /// toward its current name. Throws [GitException] when git fails.
  static Map<String, int> commitCounts({
    required String since,
    required String projectRoot,
  }) {
    if (since.isEmpty || since.startsWith('-')) {
      throw GitException('metrics: churn_since: "$since" is not a git date.');
    }
    final root = _real(projectRoot);
    final top = _real(_git(['rev-parse', '--show-toplevel'], root).trim());
    final out = _git([
      'log',
      // Ignore user config that changes the output (log.showSignature
      // prints to stdout; diff.relative makes paths cwd-relative).
      '--no-show-signature',
      '--no-relative',
      '--no-merges',
      '--no-ext-diff',
      '--no-color',
      '--name-status',
      '-M',
      '-z',
      '--format=%x01',
      '--since=$since',
      '--',
    ], root);
    // Newest first. Per commit: `\x01`, then status tokens (with a leading
    // newline) each followed by one path, or two (old, new) for R/C.
    final counts = <String, int>{};
    final renamedTo = <String, String>{};
    final touched = <String>{};
    void flush() {
      for (final f in touched) {
        counts[f] = (counts[f] ?? 0) + 1;
      }
      touched.clear();
    }

    final tokens = out.split('\u0000');
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i].trim();
      if (token.isEmpty) continue;
      if (token == '\u0001') {
        flush();
        continue;
      }
      final status = token[0];
      if ((status == 'R' || status == 'C') && i + 2 < tokens.length) {
        final old = tokens[i + 1];
        final current = renamedTo[tokens[i + 2]] ?? tokens[i + 2];
        touched.add(current);
        if (status == 'R') renamedTo[old] = current;
        i += 2;
      } else if (i + 1 < tokens.length) {
        final path = tokens[i + 1];
        touched.add(renamedTo[path] ?? path);
        i += 1;
      }
    }
    flush();
    return {
      for (final MapEntry(:key, :value) in counts.entries)
        ?_projectPath(key, root: root, top: top): value,
    };
  }

  static String? _projectPath(
    String repoPath, {
    required String root,
    required String top,
  }) => _projectPaths([repoPath], root: root, top: top).firstOrNull;

  static void _checkRef(String ref) {
    // git would read `-…` as an option (e.g. `--output=<file>`).
    if (ref.isEmpty || ref.startsWith('-')) {
      throw GitException('--since: "$ref" is not a git ref.');
    }
  }

  /// [repoPaths] (relative to the repository [top]) that lie inside [root],
  /// made relative to [root] with `/` separators.
  static Set<String> _projectPaths(
    List<String> repoPaths, {
    required String root,
    required String top,
  }) => {
    for (final repoPath in repoPaths)
      if (p.isWithin(root, p.join(top, repoPath)))
        p.relative(p.join(top, repoPath), from: root).replaceAll(r'\', '/'),
  };

  static String _real(String path) {
    try {
      return p.normalize(Directory(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      throw GitException('--since: directory not found: $path');
    }
  }

  static List<String> _nulSplit(String s) =>
      s.split('\u0000').where((x) => x.isNotEmpty).toList();

  static String _git(
    List<String> args,
    String cwd, {
    String? ref,
    Map<String, String>? environment,
  }) {
    final ProcessResult r;
    try {
      // git prints paths as UTF-8; the default (systemEncoding) is the ANSI
      // code page on Windows and garbles non-ASCII file names.
      r = Process.runSync(
        'git',
        args,
        workingDirectory: cwd,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException {
      throw const GitException('--since needs git on PATH.');
    }
    if (r.exitCode == 0) return r.stdout as String;
    final err = (r.stderr as String)
        .trim()
        .split('\n')
        .first
        .trim()
        .replaceFirst(RegExp(r'\.$'), '');
    // Skip `-c key=value` to name the git command in the message.
    final command = args.firstWhere(
      (a) => !a.startsWith('-') && !a.contains('='),
      orElse: () => args.first,
    );
    throw GitException(errorMessage(err, command: command, ref: ref));
  }

  /// The message for a failed `git <command>`, from git's first stderr line
  /// [stderr]. [ref] is the ref passed to `--since`, if the command used it.
  static String errorMessage(
    String stderr, {
    required String command,
    String? ref,
  }) {
    // git < 2.28 rejects --no-relative first, git < 2.30 --merge-base.
    if (RegExp(
      r'(invalid|unknown) option:? \W*(--)?(merge-base|no-relative)',
    ).hasMatch(stderr)) {
      return '--since needs git 2.30 or newer ($stderr).';
    }
    if (ref != null &&
        (stderr.contains('no merge base') ||
            stderr.contains('bad revision') ||
            stderr.contains('unknown revision'))) {
      return '--since: cannot compare with "$ref": $stderr. Check that the '
          'ref exists locally; in CI, fetch the base branch with full history '
          '(actions/checkout `fetch-depth: 0`).';
    }
    return '--since: git $command failed: $stderr';
  }
}
