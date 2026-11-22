import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

const _layers = '''
layers:
  presentation:
    patterns: ["lib/ui/**"]
  data:
    patterns: ["lib/data/**"]
  domain:
    patterns: ["lib/domain/**"]
''';

ArchGuardConfig _config([String yaml = _layers]) =>
    ArchGuardConfig.parse(yaml, rootPath: Directory.systemTemp.path);

ScanResult _scan(Map<String, String> sources) =>
    ProjectScanner.scanSources(packageName: 'app', sources: sources);

GraphDiff _diff(
  Map<String, String> before,
  Map<String, String> after, {
  String yaml = _layers,
}) => GraphDiff.compute(
  base: 'abc',
  before: _scan(before),
  after: _scan(after),
  config: _config(yaml),
);

void main() {
  const a = 'lib/ui/a.dart';
  const b = 'lib/data/b.dart';
  const importB = "import 'package:app/data/b.dart';\n";

  test('new cross-layer import is reported with its import', () {
    final d = _diff({a: '', b: ''}, {a: importB, b: ''});
    final e = d.groupEdges.single;
    expect([e.kind, e.from, e.to], ['layer', 'presentation', 'data']);
    expect(e.imports.single.from, a);
    expect(e.imports.single.to, b);
    expect(e.imports.single.line, 1);
    expect(d.isEmpty, isFalse);
  });

  test('edge between already connected layers is not new', () {
    final d = _diff(
      {a: importB, b: ''},
      {a: importB, b: '', 'lib/ui/c.dart': importB},
    );
    expect(d.groupEdges, isEmpty);
  });

  test('removed edge is not reported', () {
    final d = _diff({a: importB, b: ''}, {a: '', b: ''});
    expect(d.groupEdges, isEmpty);
  });

  test('file moved within its layer adds nothing', () {
    final d = _diff({a: importB, b: ''}, {'lib/ui/sub/a.dart': importB, b: ''});
    expect(d.isEmpty, isTrue);
    expect(d.coupling.map((c) => c.file), isNot(contains('lib/ui/sub/a.dart')));
  });

  test('ungrouped files are ignored', () {
    final d = _diff(
      {'lib/main.dart': '', b: ''},
      {'lib/main.dart': importB, b: ''},
    );
    expect(d.groupEdges, isEmpty);
  });

  test('new package per layer, dart: skipped', () {
    const x = 'lib/domain/x.dart';
    final d = _diff(
      {x: ''},
      {x: "import 'package:http/http.dart';\nimport 'dart:io';\n"},
    );
    expect(d.packages.map((p) => '${p.kind} ${p.group} ${p.package}'), [
      'layer domain http',
    ]);
  });

  test('a package the layer already used is not new', () {
    const x = 'lib/domain/x.dart';
    const y = 'lib/domain/y.dart';
    const http = "import 'package:http/http.dart';\n";
    final d = _diff({x: http, y: ''}, {x: http, y: http});
    expect(d.packages, isEmpty);
  });

  test('coupling growth ordered and capped', () {
    // t1..t7 exist on both sides; t<i> gains i importers. The importers
    // s1..s7 and n.dart are new, so they are not listed.
    final before = <String, String>{
      for (var i = 1; i <= 7; i++) 'lib/t$i.dart': '',
    };
    final after = <String, String>{
      ...before,
      for (var j = 1; j <= 7; j++)
        'lib/s$j.dart': [
          for (var i = j; i <= 7; i++) "import 't$i.dart';",
          "import 'n.dart';",
        ].join('\n'),
      'lib/n.dart': '',
    };
    final d = _diff(before, after);
    expect(d.coupling, hasLength(GraphDiff.maxCouplingItems));
    expect(d.coupling.first.file, 'lib/t7.dart');
    expect(d.coupling.first.fanInBefore, 0);
    expect(d.coupling.first.fanInAfter, 7);
    expect(d.coupling.first.growth, 7);
    expect(d.coupling.map((c) => c.file), isNot(contains('lib/n.dart')));
  });

  test('modules', () {
    const cart = 'lib/features/cart/cart.dart';
    const auth = 'lib/features/auth/auth.dart';
    final d = _diff(
      {cart: '', auth: ''},
      {cart: "import '../auth/auth.dart';\n", auth: ''},
      yaml: 'modules:\n  roots: ["lib/features/*"]\n',
    );
    expect(d.groupEdges.map((e) => '${e.kind} ${e.from} ${e.to}'), [
      'module cart auth',
    ]);
  });

  test('workspace members', () {
    const members = [
      WorkspacePackage(
        name: 'a',
        packagePath: 'packages/a',
        libPath: 'packages/a/lib',
      ),
      WorkspacePackage(
        name: 'b',
        packagePath: 'packages/b',
        libPath: 'packages/b/lib',
      ),
    ];
    ScanResult withMembers(ScanResult s) => ScanResult(
      packageName: s.packageName,
      files: s.files,
      edges: s.edges,
      packageImports: s.packageImports,
      packages: members,
    );
    const fa = 'packages/a/lib/a.dart';
    const fb = 'packages/b/lib/b.dart';
    final d = GraphDiff.compute(
      base: 'abc',
      before: withMembers(_scan({fa: '', fb: ''})),
      after: withMembers(_scan({fa: "import '../../b/lib/b.dart';\n", fb: ''})),
      config: _config(''),
    );
    expect(d.groupEdges.map((e) => '${e.kind} ${e.from} ${e.to}'), [
      'member a b',
    ]);
  });

  test('restrictTo drops files, edges and package imports', () {
    const gen = 'lib/ui/di.config.dart';
    final s = _scan({
      a: '',
      b: '',
      gen: "${importB}import 'package:get_it/get_it.dart';\n",
    });
    final r = GraphDiff.restrictTo(s, {a, b});
    expect(r.files.keys, unorderedEquals([a, b]));
    expect(r.edges, isEmpty);
    expect(r.packageImports, isEmpty);
    expect(r.packageName, 'app');
  });

  test('toJson shape', () {
    final d = _diff(
      {a: '', b: '', 'lib/domain/x.dart': ''},
      {
        a: importB,
        b: '',
        'lib/domain/x.dart': "import 'package:http/http.dart';\n",
      },
    );
    final json = d.toJson();
    expect(json.keys, ['base', 'groupEdges', 'packages', 'coupling']);
    expect(json['base'], 'abc');
    expect((json['groupEdges']! as List).single, {
      'kind': 'layer',
      'from': 'presentation',
      'to': 'data',
      'imports': [
        {'from': a, 'line': 1, 'to': b},
      ],
    });
    expect((json['packages']! as List).single, {
      'kind': 'layer',
      'group': 'domain',
      'package': 'http',
    });
    final coupling = (json['coupling']! as List).cast<Map>();
    expect(coupling.first['fanIn'], [0, 1]);
    expect(coupling.first['file'], b);
  });
}
