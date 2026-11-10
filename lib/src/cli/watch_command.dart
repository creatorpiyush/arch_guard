import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'run.dart';

const _configFiles = {'arch_guard.yaml', 'pubspec.yaml', 'dep_graph.yaml'};

/// Whether a change to [relativePath] (relative to the project, `/` or `\`
/// separators) should re-run the check: a Dart file, a config file or the
/// baseline. A path ending in `/` is a folder that was moved or deleted,
/// which may have held Dart files, so it counts too. Paths under `build/` or
/// a segment starting with `.` (`.git`, `.dart_tool`) never count.
bool isRelevantChange(
  String relativePath, {
  required String baselineRelativePath,
}) {
  final path = relativePath.replaceAll(r'\', '/');
  if (path == baselineRelativePath.replaceAll(r'\', '/')) return true;
  final segments = path.split('/');
  if (segments.any((s) => s.startsWith('.') || s == 'build')) return false;
  return path.endsWith('.dart') ||
      path.endsWith('/') ||
      _configFiles.contains(segments.last);
}

/// Runs [runOnce] with [args] at the start and again after each burst of
/// relevant [changes] (paths relative to [projectRoot]), [debounce] after
/// the last event, until [stop] completes. Runs never overlap; changes
/// during a run cause one more run afterwards.
///
/// Returns `0` when stopped, `64` if the first run rejects the arguments,
/// and `2` if the file watcher fails.
Future<int> runWatch({
  required List<String> args,
  required String projectRoot,
  required String baselineRelativePath,
  Future<int> Function(List<String>)? runOnce,
  Stream<String>? changes,
  Future<void>? stop,
  Duration debounce = const Duration(milliseconds: 300),
}) async {
  final run = runOnce ?? runCli;
  final done = Completer<int>();
  var running = false;
  var pending = false;
  Timer? timer;

  Future<int> runAndReport() async {
    if (stdout.hasTerminal) stdout.write('\x1B[2J\x1B[H');
    int code;
    try {
      code = await run(args);
    } catch (e) {
      // A file deleted mid-scan must not end the watch.
      stderr.writeln('Error: $e');
      code = 2;
    }
    final time = DateTime.now().toIso8601String().substring(11, 19);
    stdout.writeln(
      'Watching $projectRoot for changes (Ctrl+C to stop). '
      'Last run $time, exit $code.',
    );
    return code;
  }

  Future<void> trigger() async {
    if (running) {
      pending = true;
      return;
    }
    running = true;
    do {
      pending = false;
      await runAndReport();
    } while (pending && !done.isCompleted);
    running = false;
  }

  // Subscribe before the first run so its edits are not missed.
  final sub = (changes ?? _watch(projectRoot))
      .where(
        (path) =>
            isRelevantChange(path, baselineRelativePath: baselineRelativePath),
      )
      .listen(
        (_) {
          timer?.cancel();
          timer = Timer(debounce, trigger);
        },
        onError: (Object e) {
          stderr.writeln('Error: file watcher failed: $e');
          if (!done.isCompleted) done.complete(2);
        },
      );

  running = true;
  final first = await runAndReport();
  running = false;
  if (first == 64) {
    timer?.cancel();
    await sub.cancel();
    return 64;
  }
  if (pending) unawaited(trigger());

  unawaited(
    (stop ?? ProcessSignal.sigint.watch().first).then((_) {
      if (!done.isCompleted) done.complete(0);
    }),
  );
  final code = await done.future;
  timer?.cancel();
  await sub.cancel();
  return code;
}

/// Changed paths under [root], relative to it. See [_changes].
Stream<String> _watch(String root) {
  // macOS reports /private/var/... for a root under /var/...
  final real = Directory(root).resolveSymbolicLinksSync();
  String relative(String path) =>
      p.relative(path, from: p.isWithin(real, path) ? real : root);
  final paths = Platform.isLinux
      ? _watchEachDirectory(root)
      : Directory(root).watch(recursive: true).expand(_changes);
  return paths.map(
    (path) => path.endsWith('/')
        ? '${relative(path.substring(0, path.length - 1))}/'
        : relative(path),
  );
}

/// The paths [e] changed. Both ends of a move count, so an editor that saves
/// through a temp file and a rename still counts.
///
/// Watchers report a moved or deleted folder, not the files in it, so:
/// - a new or moved-in folder yields the files inside it;
/// - a removed folder yields `<path>/`. A deleted path is not marked as a
///   folder, so any deleted path without an extension is treated as one.
Iterable<String> _changes(FileSystemEvent e) sync* {
  final removed =
      e.type == FileSystemEvent.delete ||
      (e is FileSystemMoveEvent && e.isDirectory);
  final folder = e.isDirectory || p.extension(e.path).isEmpty;
  yield removed && folder ? '${e.path}/' : e.path;

  final added = e is FileSystemMoveEvent
      ? e.destination
      : (e.type == FileSystemEvent.create ? e.path : null);
  if (added == null) return;
  if (added != e.path) yield added;
  if (e.isDirectory) yield* _filesUnder(added);
}

/// Files under [dir], skipping folders [isRelevantChange] ignores.
Iterable<String> _filesUnder(String dir) sync* {
  List<FileSystemEntity> entries;
  try {
    entries = Directory(dir).listSync(followLinks: false);
  } on FileSystemException {
    return; // Removed again already.
  }
  for (final entity in entries) {
    if (entity is! Directory) {
      yield entity.path;
    } else if (!_skippedDirectory(entity.path)) {
      yield* _filesUnder(entity.path);
    }
  }
}

bool _skippedDirectory(String path) {
  final name = p.basename(path);
  return name.startsWith('.') || name == 'build';
}

/// Linux ignores `recursive: true` and reports only [root]'s own entries, so
/// watch every directory, and new ones as they appear. Skips the directories
/// [isRelevantChange] ignores, which also keeps `.git` and `.dart_tool` from
/// using up inotify watches.
Stream<String> _watchEachDirectory(String root) {
  final subs = <String, StreamSubscription<FileSystemEvent>>{};
  late final StreamController<String> out;

  void watchTree(String dir) {
    if (subs.containsKey(dir) || _skippedDirectory(dir) && dir != root) return;
    subs[dir] = Directory(dir).watch().listen(
      (e) {
        _changes(e).forEach(out.add);
        final added = e is FileSystemMoveEvent ? e.destination : e.path;
        if (e.isDirectory &&
            e.type != FileSystemEvent.delete &&
            added != null) {
          watchTree(added);
        }
      },
      onError: out.addError,
      onDone: () => subs.remove(dir),
    );
    try {
      for (final entity in Directory(dir).listSync(followLinks: false)) {
        if (entity is Directory) watchTree(entity.path);
      }
    } on FileSystemException {
      // Removed again already.
    }
  }

  out = StreamController<String>(
    onListen: () => watchTree(root),
    onCancel: () => Future.wait([for (final s in subs.values) s.cancel()]),
  );
  return out.stream;
}
