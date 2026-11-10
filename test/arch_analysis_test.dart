import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  void write(String path, String content) {
    final file = File(p.join(project.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('arch_guard_analysis_');
    write('pubspec.yaml', 'name: app\n');
    write('arch_guard.yaml', '''
max_scc_size: 1
layers:
  domain:
    patterns: ["lib/domain/**"]
    forbidden_packages: [flutter]
  data:
    patterns: ["lib/data/**"]
    allowed_imports: [domain]
''');
    write(
      'lib/domain/a.dart',
      "import '../data/b.dart';\nimport 'package:flutter/widgets.dart';\n",
    );
    write('lib/data/b.dart', "import '../domain/a.dart';\n");
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('collects every kind of problem', () async {
    final a = await ArchAnalysis.run(projectPath: project.path);
    expect(a.cycles, hasLength(1));
    expect(a.layerViolations.single.sourceFile, 'lib/domain/a.dart');
    expect(a.packageViolations.single.package, 'flutter');
    expect(a.oversizedCycles, hasLength(1));
    expect(a.baseline, isNull);
    expect(a.newLayerViolations, a.layerViolations);
  });

  test('failures follow the CLI rules', () async {
    final a = await ArchAnalysis.run(projectPath: project.path);
    final all = a.failures();
    expect(all.where((f) => f.startsWith('Circular dependency')), hasLength(1));
    expect(all.where((f) => f.startsWith('Layer violation')), hasLength(1));
    expect(all.where((f) => f.startsWith('Forbidden package')), hasLength(1));
    expect(all.where((f) => f.startsWith('Too large')), hasLength(1));

    // max_scc_size still fails with failOnCycle: false, like --no-fail-on-cycle.
    final noCycles = a.failures(failOnCycle: false);
    expect(noCycles.where((f) => f.startsWith('Circular dependency')), isEmpty);
    expect(noCycles.where((f) => f.startsWith('Too large')), hasLength(1));
  });

  test('fail_on_layer_violation: false drops layer failures only', () async {
    write('arch_guard.yaml', '''
fail_on_layer_violation: false
layers:
  domain:
    patterns: ["lib/domain/**"]
    forbidden_packages: [flutter]
  data:
    patterns: ["lib/data/**"]
''');
    final a = await ArchAnalysis.run(projectPath: project.path);
    final f = a.failures(failOnCycle: false);
    expect(f.where((x) => x.startsWith('Layer violation')), isEmpty);
    expect(f.where((x) => x.startsWith('Forbidden package')), hasLength(1));
  });

  test('a baseline turns known problems into non-failures', () async {
    final first = await ArchAnalysis.run(projectPath: project.path);
    Baseline.capture(
      cycles: first.cycles,
      layerViolations: first.layerViolations,
      packageViolations: first.packageViolations,
    ).save(first.baselinePath);

    final again = await ArchAnalysis.run(projectPath: project.path);
    expect(again.baseline, isNotNull);
    expect(again.failures(), isEmpty);

    final ignoring = await ArchAnalysis.run(
      projectPath: project.path,
      useBaseline: false,
    );
    expect(ignoring.failures(), isNotEmpty);
  });

  test('metric limits fail and hotspots are listed', () async {
    write('arch_guard.yaml', 'metrics:\n  max_fan_out: 1\n  hotspots: 1\n');
    write('lib/domain/c.dart', '');
    // Two project imports (b.dart, c.dart) against a limit of 1.
    write('lib/domain/a.dart', "import '../data/b.dart';\nimport 'c.dart';\n");
    final a = await ArchAnalysis.run(projectPath: project.path);
    expect(a.metricViolations.single.file, 'lib/domain/a.dart');
    expect(a.metricViolations.single.value, 2);
    expect(
      a.failures(failOnCycle: false).where((f) => f.startsWith('Metric limit')),
      hasLength(1),
    );
    expect(a.hotspots, hasLength(1));
  });

  group('ignore comments', () {
    const ignoreLayer = '// ignore: arch_guard_lint/layer_violation\n';
    const ignoreCycle = '// ignore: arch_guard_lint/circular_dependency\n';

    test('ignored layer import is not a violation', () async {
      write('arch_guard.yaml', 'preset: clean_architecture\n');
      write('lib/domain/u.dart', "${ignoreLayer}import '../data/d.dart';\n");
      write('lib/data/d.dart', '');
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(
        a.layerViolations.where((v) => v.sourceFile == 'lib/domain/u.dart'),
        isEmpty,
      );
    });

    test('ignore on a barrel import hides the via violation', () async {
      write('arch_guard.yaml', 'preset: clean_architecture\n');
      write('lib/domain/u.dart', "${ignoreLayer}import '../exports.dart';\n");
      write('lib/exports.dart', "export 'data/d.dart';\n");
      write('lib/data/d.dart', '');
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(
        a.layerViolations.where((v) => v.sourceFile == 'lib/domain/u.dart'),
        isEmpty,
      );
    });

    test('ignored forbidden package', () async {
      write(
        'lib/domain/a.dart',
        "import 'package:flutter/widgets.dart'; "
            '// ignore: arch_guard_lint/forbidden_package\n',
      );
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(a.packageViolations, isEmpty);
    });

    test('ignored import breaks a two-file cycle', () async {
      write('lib/data/b.dart', "${ignoreCycle}import '../domain/a.dart';\n");
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(a.cycles, isEmpty);
      expect(
        a.scan.edges.map((e) => '${e.from}>${e.to}'),
        contains('lib/data/b.dart>lib/domain/a.dart'),
      );
    });

    test(
      'cycle with another path survives, hint avoids the ignored import',
      () async {
        write('arch_guard.yaml', 'max_scc_size: 10\n');
        write('lib/a.dart', "import 'b.dart';\n");
        write(
          'lib/b.dart',
          "${ignoreCycle}import 'a.dart';\nimport 'c.dart';\n",
        );
        write('lib/c.dart', "import 'a.dart';\n");
        final a = await ArchAnalysis.run(projectPath: project.path);
        final cycle = a.cycles.singleWhere(
          (c) => c.files.contains('lib/c.dart'),
        );
        expect(cycle.files.toSet(), {'lib/a.dart', 'lib/b.dart', 'lib/c.dart'});
        final hint = cycle.scc!.suggestedBreak!;
        expect('${hint.from}>${hint.to}', isNot('lib/b.dart>lib/a.dart'));
      },
    );
  });

  group('since', () {
    void git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: project.path);
      if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
    }

    setUp(() {
      git(['init', '-q', '-b', 'main']);
      git(['config', 'user.email', 't@example.com']);
      git(['config', 'user.name', 'T']);
      git(['add', '.']);
      git(['commit', '-qm', 'base']);
    });

    test('keeps only problems touching changed files', () async {
      // Base: domain/a.dart -> data/b.dart is a layer violation and a cycle.
      write(
        'lib/data/c.dart',
        "import '../domain/a.dart';\n",
      ); // untracked, fine
      final none = await ArchAnalysis.run(
        projectPath: project.path,
        since: 'main',
      );
      expect(none.changedFiles, {'lib/data/c.dart'});
      expect(none.layerViolations, isEmpty);
      expect(none.cycles, isEmpty);

      write('lib/domain/a.dart', "import '../data/b.dart';\n// edited\n");
      final some = await ArchAnalysis.run(
        projectPath: project.path,
        since: 'main',
      );
      expect(some.layerViolations.single.sourceFile, 'lib/domain/a.dart');
      expect(some.cycles, hasLength(1));
    });

    test('keeps a fan-in violation caused by a changed importer', () async {
      write('arch_guard.yaml', 'metrics:\n  max_fan_in: 1\n');
      write('lib/data/c.dart', "import '../domain/a.dart';\n");
      final a = await ArchAnalysis.run(
        projectPath: project.path,
        since: 'main',
      );
      expect(a.metricViolations.map((v) => v.file), ['lib/domain/a.dart']);
    });

    test('baseline fixed counts match a full run', () async {
      final full = await ArchAnalysis.run(projectPath: project.path);
      Baseline.capture(
        cycles: full.cycles,
        layerViolations: full.layerViolations,
        packageViolations: full.packageViolations,
      ).save(full.baselinePath);
      write('lib/data/c.dart', '');
      final narrowed = await ArchAnalysis.run(
        projectPath: project.path,
        since: 'main',
      );
      expect(narrowed.baseline!.fixedViolationCount, 0);
      expect(narrowed.baseline!.fixedCycleCount, 0);
    });

    test('keeps only unused files that changed', () async {
      write('arch_guard.yaml', 'unused_files: true\n');
      write('lib/main.dart', "import 'domain/a.dart';\n");
      write('lib/old.dart', '');
      git(['add', '.']);
      git(['commit', '-qm', 'old dead file']);
      write('lib/new_dead.dart', '');
      final a = await ArchAnalysis.run(
        projectPath: project.path,
        since: 'main',
      );
      expect(a.unusedFiles, ['lib/new_dead.dart']);
    });
  });

  group('unused files', () {
    setUp(() {
      write('lib/main.dart', "import 'domain/a.dart';\n");
      write('lib/old.dart', '');
    });

    bool unusedLine(String f) => f.startsWith('Unused file');

    test('fail with fail: true', () async {
      write('arch_guard.yaml', 'unused_files:\n  fail: true\n');
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(a.unusedFiles, ['lib/old.dart']);
      expect(
        a.failures(),
        contains('Unused file: lib/old.dart (no entry point reaches it).'),
      );
    });

    test('are reported but do not fail by default', () async {
      write('arch_guard.yaml', 'unused_files: true\n');
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(a.unusedFiles, ['lib/old.dart']);
      expect(a.failures().where(unusedLine), isEmpty);
    });

    test('are not checked without the config key', () async {
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(a.unusedFiles, isEmpty);
    });

    test('no entry point warns instead of reporting', () async {
      write('arch_guard.yaml', 'unused_files:\n  fail: true\n');
      File(p.join(project.path, 'lib/main.dart')).deleteSync();
      final a = await ArchAnalysis.run(projectPath: project.path);
      expect(a.unusedFiles, isEmpty);
      expect(
        a.warnings.join(),
        contains('unused_files: no scanned file matches an entry point'),
      );
      expect(a.failures().where(unusedLine), isEmpty);
    });
  });
}
