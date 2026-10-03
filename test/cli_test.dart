import 'dart:io';

import 'package:arch_guard/src/cli/run.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CLI execution', () {
    late Directory outDir;

    setUp(() {
      outDir = Directory.systemTemp.createTempSync('arch_guard_cli_');
    });

    tearDown(() {
      outDir.deleteSync(recursive: true);
    });

    test('returns exit code 64 for invalid flag', () async {
      final code = await runCli(['--invalid-flag-123']);
      expect(code, equals(64));
    });

    test('returns exit code 2 for non-existent directory', () async {
      final code = await runCli(['non_existent_dir_xyz_123']);
      expect(code, equals(2));
    });

    test('returns exit code 1 when cycles found on sample_project', () async {
      final code = await runCli([
        'example/sample_project',
        '-f',
        'all',
        '-o',
        outDir.path,
      ]);
      expect(code, equals(1));
    });

    test('returns exit code 0 when --explain passed', () async {
      final code = await runCli([
        'example/sample_project',
        '--explain',
        'lib/services/auth_service.dart',
      ]);
      expect(code, equals(0));
    });

    test('returns exit code 0 for --format json', () async {
      final code = await runCli([
        'example/sample_project',
        '--no-fail-on-cycle',
        '-f',
        'json',
        '-o',
        outDir.path,
      ]);
      expect(code, equals(0));
    });

    test(
      'returns exit code 0 for --format mermaid with scope cycles',
      () async {
        final code = await runCli([
          'example/sample_project',
          '--no-fail-on-cycle',
          '-f',
          'mermaid',
          '--scope',
          'cycles',
          '-o',
          outDir.path,
        ]);
        expect(code, equals(0));
      },
    );

    test('returns exit code 0 when --no-fail-on-cycle passed', () async {
      final code = await runCli([
        'example/sample_project',
        '--no-fail-on-cycle',
        '-f',
        'all',
        '-o',
        outDir.path,
      ]);
      expect(code, equals(0));
    });

    test('writes export files to the requested output directory', () async {
      await runCli([
        'example/sample_project',
        '--no-fail-on-cycle',
        '-f',
        'json',
        '-o',
        outDir.path,
      ]);
      expect(
        File(p.join(outDir.path, 'dependency_graph.json')).existsSync(),
        isTrue,
      );
    });

    test('--version prints the package version', () async {
      expect(await runCli(['--version']), equals(0));
    });

    test('writes SARIF and Markdown reports', () async {
      final code = await runCli([
        'example/sample_project',
        '--no-fail-on-cycle',
        '--no-color',
        '-f',
        'sarif',
        '-f',
        'markdown',
        '-o',
        outDir.path,
      ]);
      expect(code, equals(0));
      expect(
        File(p.join(outDir.path, 'arch_guard.sarif')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(outDir.path, 'arch_guard_report.md')).existsSync(),
        isTrue,
      );
    });

    group('baseline', () {
      late String root;

      void writeFile(String name, String content) =>
          File(p.join(root, 'lib', name)).writeAsStringSync(content);

      setUp(() {
        // a <-> b form a cycle; c is standalone for now.
        root = p.join(outDir.path, 'project');
        Directory(p.join(root, 'lib')).createSync(recursive: true);
        File(p.join(root, 'pubspec.yaml')).writeAsStringSync('name: legacy\n');
        writeFile('a.dart', "import 'b.dart';\n");
        writeFile('b.dart', "import 'a.dart';\n");
        writeFile('c.dart', '');
      });

      Future<int> run([List<String> extra = const []]) =>
          runCli([root, '--no-color', ...extra]);

      test('fails only on cycles added after the baseline', () async {
        expect(await run(), equals(1));

        expect(await run(['--update-baseline']), equals(0));
        expect(
          File(p.join(root, 'arch_guard_baseline.json')).existsSync(),
          isTrue,
        );
        expect(await run(), equals(0));

        // c <-> a merges into the known cycle, making it grow: new problem.
        writeFile('c.dart', "import 'a.dart';\n");
        writeFile('a.dart', "import 'b.dart';\nimport 'c.dart';\n");
        expect(await run(), equals(1));
      });

      test('honours a custom --baseline path', () async {
        final custom = p.join(outDir.path, 'custom_baseline.json');
        expect(
          await run(['--update-baseline', '--baseline', custom]),
          equals(0),
        );
        expect(File(custom).existsSync(), isTrue);
        expect(await run(['--baseline', custom]), equals(0));
        expect(await run(), equals(1));
      });

      test('exits 2 when the baseline file is invalid', () async {
        File(
          p.join(root, 'arch_guard_baseline.json'),
        ).writeAsStringSync('not json');
        expect(await run(), equals(2));
      });
    });

    group('max_scc_size', () {
      Future<int> runWithLimit(int limit) {
        // Three files importing each other in a ring form one 3-file SCC.
        final root = p.join(outDir.path, 'project');
        Directory(p.join(root, 'lib')).createSync(recursive: true);
        File(p.join(root, 'pubspec.yaml')).writeAsStringSync('name: ring\n');
        File(
          p.join(root, 'arch_guard.yaml'),
        ).writeAsStringSync('max_scc_size: $limit\n');
        for (final (name, next) in [('a', 'b'), ('b', 'c'), ('c', 'a')]) {
          File(
            p.join(root, 'lib', '$name.dart'),
          ).writeAsStringSync("import '$next.dart';\n");
        }
        return runCli([root, '--no-fail-on-cycle', '--no-color']);
      }

      test('fails when an SCC exceeds the limit', () async {
        expect(await runWithLimit(2), equals(1));
      });

      test('passes when every SCC is within the limit', () async {
        expect(await runWithLimit(3), equals(0));
      });
    });
  });
}
