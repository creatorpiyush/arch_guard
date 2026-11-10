import 'dart:async';
import 'dart:io';

import 'package:arch_guard/src/cli/watch_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('relevant paths', () {
    bool r(String path) => isRelevantChange(
      path,
      baselineRelativePath: 'arch_guard_baseline.json',
    );
    expect(r('lib/a.dart'), isTrue);
    expect(r(r'lib\a.dart'), isTrue);
    expect(r('arch_guard.yaml'), isTrue);
    expect(r('pubspec.yaml'), isTrue);
    expect(r('packages/a/pubspec.yaml'), isTrue);
    expect(r('arch_guard_baseline.json'), isTrue);
    expect(r('arch_guard_report.html'), isFalse);
    expect(r('arch_guard_output/dependency_graph.json'), isFalse);
    expect(r('.dart_tool/x.dart'), isFalse);
    expect(r('build/gen.dart'), isFalse);
    expect(r(r'packages\a\build\gen.dart'), isFalse);
    expect(r('README.md'), isFalse);
    expect(r('lib/feature/'), isTrue); // folder moved or deleted
    expect(r(r'lib\feature/'), isTrue);
    expect(r('build/x/'), isFalse);
    expect(r('.git/refs/'), isFalse);
  });

  group('runWatch', () {
    const fast = Duration(milliseconds: 20);
    const settle = Duration(milliseconds: 60);
    late StreamController<String> changes;
    late Completer<void> stop;
    late List<List<String>> calls;
    late Future<int> watching;

    void start({
      List<String> args = const ['lib'],
      Future<int> Function(List<String>)? runOnce,
    }) {
      changes = StreamController<String>();
      stop = Completer<void>();
      calls = [];
      watching = runWatch(
        args: args,
        projectRoot: '/project',
        baselineRelativePath: 'arch_guard_baseline.json',
        runOnce:
            runOnce ??
            (a) async {
              calls.add(a);
              return 0;
            },
        changes: changes.stream,
        stop: stop.future,
        debounce: fast,
      );
    }

    tearDown(() async {
      if (!stop.isCompleted) stop.complete();
      await watching;
    });

    test('runs once at start', () async {
      start();
      await Future<void>.delayed(settle);
      expect(calls, hasLength(1));
    });

    test('three quick events, one rerun', () async {
      start();
      await Future<void>.delayed(settle);
      for (var i = 0; i < 3; i++) {
        changes.add('lib/a.dart');
      }
      await Future<void>.delayed(settle);
      expect(calls, hasLength(2));
    });

    test('irrelevant change, no rerun', () async {
      start();
      await Future<void>.delayed(settle);
      changes.add('README.md');
      await Future<void>.delayed(settle);
      expect(calls, hasLength(1));
    });

    test('change during a run, one follow-up', () async {
      final gate = Completer<void>();
      calls = [];
      start(
        runOnce: (a) async {
          calls.add(a);
          if (calls.length == 2) await gate.future;
          return 0;
        },
      );
      await Future<void>.delayed(settle);
      changes.add('lib/a.dart');
      await Future<void>.delayed(settle);
      expect(calls, hasLength(2)); // blocked in the second run
      changes.add('lib/a.dart');
      await Future<void>.delayed(settle);
      changes.add('lib/b.dart');
      await Future<void>.delayed(settle);
      gate.complete();
      await Future<void>.delayed(settle);
      expect(calls, hasLength(3));
    });

    test('passes args through unchanged', () async {
      start(args: ['example', '-f', 'json']);
      await Future<void>.delayed(settle);
      expect(calls.single, ['example', '-f', 'json']);
    });

    test('stop returns 0', () async {
      start();
      await Future<void>.delayed(settle);
      stop.complete();
      expect(await watching, 0);
    });

    test('first run 64 ends the watch', () async {
      start(runOnce: (_) async => 64);
      expect(await watching, 64);
    });

    test('a throwing run keeps watching', () async {
      var n = 0;
      start(
        runOnce: (_) async {
          if (++n == 1) throw StateError('boom');
          return 0;
        },
      );
      await Future<void>.delayed(settle);
      changes.add('lib/a.dart');
      await Future<void>.delayed(settle);
      expect(n, 2);
    });

    test('watcher error returns 2', () async {
      start();
      await Future<void>.delayed(settle);
      changes.addError(const FileSystemException('inotify limit'));
      expect(await watching, 2);
    });
  });

  test(
    'real filesystem: nested edits and new folders trigger a rerun',
    () async {
      final root = Directory.systemTemp.createTempSync('arch_guard_watch_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      final deep = File(p.join(root.path, 'lib', 'src', 'deep', 'x.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// v1\n');

      var calls = 0;
      final stop = Completer<void>();
      final watching = runWatch(
        args: const [],
        projectRoot: root.path,
        baselineRelativePath: 'arch_guard_baseline.json',
        runOnce: (_) async {
          calls++;
          return 0;
        },
        stop: stop.future,
      );
      // macOS may report the setup writes above once the watch starts, so
      // count reruns from where the calls settle.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(calls, greaterThanOrEqualTo(1));
      var expected = calls;
      Future<void> expectOneRerun() async {
        expected++;
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (calls < expected && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        // Let a wrong extra run show up.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(calls, expected);
      }

      deep.writeAsStringSync('// v2\n');
      await expectOneRerun();

      // A folder created after the watch started (Linux watches each folder).
      File(p.join(root.path, 'lib', 'new', 'n.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// n\n');
      await expectOneRerun();

      stop.complete();
      expect(await watching, 0);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}
