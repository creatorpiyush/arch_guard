import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:arch_guard/src/cli/run.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  void write(String path, String content) {
    final file = File(p.join(dir.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('arch_guard_wsr_');
    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - apps/mobile\n  - packages/core\n  - packages/ui\n',
    );
    write('apps/mobile/pubspec.yaml', 'name: mobile\nresolution: workspace\n');
    write('packages/core/pubspec.yaml', 'name: core\nresolution: workspace\n');
    write('packages/ui/pubspec.yaml', 'name: ui\nresolution: workspace\n');
    write('packages/core/lib/core.dart', '');
    write('packages/ui/lib/ui.dart', "import 'package:core/core.dart';\n");
    write('apps/mobile/lib/main.dart', "import 'package:ui/ui.dart';\n");
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('scan records workspace members', () async {
    final result = await ProjectScanner(rootPath: dir.path).scan();
    expect(result.packages.map((m) => m.packagePath), [
      'apps/mobile',
      'packages/core',
      'packages/ui',
    ]);
  });

  test('config parses workspace_rules in order and drops bad globs', () {
    final config = ArchGuardConfig.parse('''
workspace_rules:
  "apps/*":
    allowed: ["packages/*"]
  core:
    allowed: []
  "packages/[x":
    allowed: ["packages/{y"]
''', rootPath: dir.path);
    expect(config.workspaceRules.keys, ['apps/*', 'core']);
    expect(config.workspaceRules['apps/*'], ['packages/*']);
    expect(config.workspaceRules['core'], isEmpty);
    expect(
      config.warnings.where((w) => w.contains('is not a valid glob')),
      hasLength(1),
    );
  });

  WorkspacePackage pkg(String name, String path) => WorkspacePackage(
    name: name,
    packagePath: path,
    libPath: path == '.' ? 'lib' : '$path/lib',
  );

  ScanResult ws(List<GraphEdge> edges) => ScanResult(
    packageName: 'root',
    files: const {},
    edges: edges,
    workspacePackageCount: 5,
    packages: [
      pkg('root', '.'),
      pkg('mobile', 'apps/mobile'),
      pkg('a', 'packages/a'),
      pkg('a_extras', 'packages/a_extras'),
      pkg('core', 'packages/core'),
    ],
  );

  ArchGuardConfig rules(String yaml) =>
      ArchGuardConfig.parse(yaml, rootPath: Directory.systemTemp.path);

  test('reports imports against the first matching rule', () {
    final config = rules('''
workspace_rules:
  core:
    allowed: []
  "packages/*":
    allowed: [core]
''');
    final v = WorkspaceValidator.validate(
      result: ws(const [
        GraphEdge(
          from: 'packages/core/lib/c.dart',
          to: 'packages/a/lib/a.dart',
          line: 2,
        ),
        GraphEdge(
          from: 'packages/a/lib/a.dart',
          to: 'packages/core/lib/c.dart',
        ),
        GraphEdge(
          from: 'packages/a_extras/lib/x.dart',
          to: 'packages/a/lib/a.dart',
          line: 7,
        ),
        GraphEdge(from: 'packages/a/lib/a.dart', to: 'packages/a/lib/b.dart'),
        GraphEdge(from: 'apps/mobile/lib/m.dart', to: 'packages/a/lib/a.dart'),
      ]),
      config: config,
    );
    expect(
      v.map((x) => '${x.sourcePackage}>${x.targetPackage}@${x.selector}'),
      ['core>a@core', 'a_extras>a@packages/*'],
    );
    expect(v.first.line, 2);
    expect(v.first.rule, contains('may not import other workspace members'));
    expect(v.last.rule, contains('may only import members matching `core`'));
  });

  test('root package files belong to "."', () {
    final config = rules('workspace_rules:\n  ".":\n    allowed: []\n');
    final v = WorkspaceValidator.validate(
      result: ws(const [
        GraphEdge(from: 'lib/main.dart', to: 'packages/core/lib/c.dart'),
      ]),
      config: config,
    );
    expect(v.single.sourcePackage, 'root');
  });

  test('unmatched selectors and allowed entries are listed', () {
    final config = rules('workspace_rules:\n  "aps/*":\n    allowed: [corr]\n');
    expect(
      WorkspaceValidator.unmatchedPatterns(
        result: ws(const []),
        config: config,
      ),
      ['aps/*', 'corr'],
    );
  });

  test(
    'end to end: CLI fails, baseline accepts, non-workspace warns',
    () async {
      write('arch_guard.yaml', '''
workspace_rules:
  "packages/core":
    allowed: []
  "packages/*":
    allowed: ["packages/core"]
  "apps/*":
    allowed: ["packages/core"]
''');
      final a = await ArchAnalysis.run(projectPath: dir.path);
      expect(
        a.workspaceViolations.map(
          (v) => '${v.sourcePackage}>${v.targetPackage}',
        ),
        ['mobile>ui'],
      );
      expect(
        a.failures(failOnCycle: false).single,
        startsWith('Workspace rule:'),
      );

      expect(await runCli([dir.path]), 1);
      expect(await runCli([dir.path, '--update-baseline']), 0);
      expect(await runCli([dir.path]), 0);
    },
  );

  test('workspace_rules in a single package only warns', () async {
    final single = Directory.systemTemp.createTempSync('arch_guard_single_');
    addTearDown(() => single.deleteSync(recursive: true));
    File(p.join(single.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
    File(
      p.join(single.path, 'arch_guard.yaml'),
    ).writeAsStringSync('workspace_rules:\n  core:\n    allowed: []\n');
    final a = await ArchAnalysis.run(projectPath: single.path);
    expect(a.workspaceViolations, isEmpty);
    expect(a.warnings, contains(contains('workspace_rules is ignored')));
  });
}
