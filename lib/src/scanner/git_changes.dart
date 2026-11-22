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
      _git(['worktree', 'add', '--detach', '--quiet', checkout, sha], root);
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

  static String _git(List<String> args, String cwd, {String? ref}) {
    final ProcessResult r;
    try {
      // git prints paths as UTF-8; the default (systemEncoding) is the ANSI
      // code page on Windows and garbles non-ASCII file names.
      r = Process.runSync(
        'git',
        args,
        workingDirectory: cwd,
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
    throw GitException(errorMessage(err, command: args.first, ref: ref));
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
