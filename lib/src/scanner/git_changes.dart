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
    // git would read `-…` as an option (e.g. `--output=<file>`).
    if (ref.isEmpty || ref.startsWith('-')) {
      throw GitException('--since: "$ref" is not a git ref.');
    }
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
    return {
      for (final repoPath in repoPaths)
        if (p.isWithin(root, p.join(top, repoPath)))
          p.relative(p.join(top, repoPath), from: root).replaceAll(r'\', '/'),
    };
  }

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
    if (stderr.contains('merge-base') &&
        RegExp('invalid option|unknown option|unrecognized').hasMatch(stderr)) {
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
