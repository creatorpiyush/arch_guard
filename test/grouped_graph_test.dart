import 'dart:convert';
import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  void write(String path, String content) {
    final f = File(p.join(project.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('arch_guard_grouped_');
    write('pubspec.yaml', 'name: app\n');
    write('arch_guard.yaml', '''
layers:
  domain:
    patterns: ["lib/domain/**"]
    allowed_imports: []
  data:
    patterns: ["lib/data/**"]
    allowed_imports: [domain]
  ui:
    patterns: ["lib/ui/**"]
    allowed_imports: [domain]
modules:
  roots: ["lib/ui/*"]
''');
    write('lib/main.dart', "import 'ui/home/page.dart';\n");
    write('lib/domain/user.dart', '');
    write('lib/domain/repo.dart', "import 'user.dart';\n");
    write('lib/data/api.dart', "import '../domain/repo.dart';\n");
    write('lib/data/cache.dart', "import '../domain/user.dart';\n");
    write(
      'lib/ui/home/page.dart',
      "import '../../domain/user.dart';\n"
          "import '../../data/api.dart';\n"
          "import '../cart/src/list.dart';\n",
    );
    write('lib/ui/cart/src/list.dart', "import '../../home/page.dart';\n");
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<ArchAnalysis> analyse() => ArchAnalysis.run(projectPath: project.path);

  test('by layer: nodes, edge counts, violations and (none)', () async {
    final g = GroupedGraph.build(await analyse(), groupBy: 'layer');
    expect(g.groups, {
      '(none)': ['lib/main.dart'],
      'data': ['lib/data/api.dart', 'lib/data/cache.dart'],
      'domain': ['lib/domain/repo.dart', 'lib/domain/user.dart'],
      'ui': ['lib/ui/cart/src/list.dart', 'lib/ui/home/page.dart'],
    });
    String edge(GroupEdge e) =>
        '${e.from}->${e.to} ${e.count}${e.violations > 0 ? ' !${e.violations}' : ''}';
    expect(g.edges.map(edge), [
      '(none)->ui 1',
      'data->domain 2',
      'ui->data 1 !1',
      'ui->domain 1',
    ]);
  });

  test('by module and folder', () async {
    final analysis = await analyse();
    final modules = GroupedGraph.build(analysis, groupBy: 'module');
    expect(modules.groups.keys, ['(none)', 'cart', 'home']);
    expect(
      modules.edges.map((e) => '${e.from}->${e.to} ${e.count} ${e.violations}'),
      contains('home->cart 1 1'),
    );

    final folders = GroupedGraph.build(analysis, groupBy: 'folder');
    expect(folders.groups.keys, ['lib', 'lib/data', 'lib/domain', 'lib/ui']);
  });

  test('by package in a single-package project', () async {
    final g = GroupedGraph.build(await analyse(), groupBy: 'package');
    expect(g.groups.keys, ['app']);
    expect(g.edges, isEmpty);
  });

  test('files limits nodes and edges (--scope cycles)', () async {
    final analysis = await analyse();
    final cyclic = {for (final c in analysis.cycles) ...c.files};
    expect(cyclic, {'lib/ui/home/page.dart', 'lib/ui/cart/src/list.dart'});
    final g = GroupedGraph.build(analysis, groupBy: 'module', files: cyclic);
    expect(g.groups.keys, ['cart', 'home']);
    expect(g.edges.map((e) => '${e.from}->${e.to}'), [
      'cart->home',
      'home->cart',
    ]);
  });

  test('folderOf', () {
    expect(GroupedGraph.folderOf('lib/main.dart'), 'lib');
    expect(GroupedGraph.folderOf('lib/features/cart/a.dart'), 'lib/features');
    expect(
      GroupedGraph.folderOf('packages/core/lib/src/a.dart'),
      'packages/core/lib/src',
    );
    expect(GroupedGraph.folderOf('bin/tool/a.dart'), 'bin');
    expect(GroupedGraph.folderOf('a.dart'), '.');
  });

  test('Mermaid, DOT and HTML render the grouped graph', () async {
    final analysis = await analyse();
    final g = GroupedGraph.build(analysis, groupBy: 'layer');

    final mermaid = MermaidExporter.exportGrouped(g);
    expect(mermaid, contains('g0["(none)<br/>1 file"]'));
    expect(mermaid, contains('g3 -->|"1, 1 violation"| g1'));
    expect(mermaid, contains('linkStyle 2 stroke:#ef4444'));

    final dot = DotExporter.exportGrouped(g);
    expect(dot, contains('"data" [label="data\\n2 files"];'));
    expect(dot, contains('"data" -> "domain" [label="2"];'));
    expect(
      dot,
      contains('"ui" -> "data" [label="1, 1 violation", color="#ef4444"'),
    );

    final html = HtmlExporter.export(
      result: analysis.scan,
      cycles: analysis.cycles,
      scope: 'all',
      grouped: g,
    );
    final json = RegExp(
      r'<script id="graph-data" type="application/json">([\s\S]*?)</script>',
    ).firstMatch(html)!.group(1)!;
    final grouped = (jsonDecode(json) as Map)['grouped'] as Map;
    expect(grouped['groupBy'], 'layer');
    expect((grouped['groups'] as List).map((g) => g['id']), [
      '(none)',
      'data',
      'domain',
      'ui',
    ]);
    expect(
      HtmlExporter.export(result: analysis.scan, cycles: analysis.cycles),
      isNot(contains('"grouped"')),
    );
  });

  test('CLI --group-by implies --scope all unless --scope is given', () {
    final out = p.join(project.path, 'out');
    ProcessResult run(List<String> extra) =>
        Process.runSync(Platform.resolvedExecutable, [
          'bin/arch_guard.dart',
          project.path,
          '--no-color',
          '-f',
          'mermaid',
          '-o',
          out,
          '--group-by',
          'layer',
          ...extra,
        ]);
    String mermaid() =>
        File(p.join(out, 'dependency_graph.mmd')).readAsStringSync();

    run([]);
    expect(mermaid(), contains('domain<br/>2 files'));

    run(['--scope', 'cycles']);
    expect(mermaid(), isNot(contains('domain')));
    expect(mermaid(), contains('ui<br/>2 files'));
  });

  test('CLI warns when --group-by has nothing to draw', () {
    final r = Process.runSync(Platform.resolvedExecutable, [
      'bin/arch_guard.dart',
      project.path,
      '--no-color',
      '--group-by',
      'layer',
    ]);
    expect(
      r.stderr,
      contains('--group-by applies to -f dot, html and mermaid'),
    );
  });
}
