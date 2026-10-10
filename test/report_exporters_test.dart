import 'dart:convert';
import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  const result = ScanResult(
    packageName: 'demo_pkg',
    files: {
      'lib/a.dart': FileNode(relativePath: 'lib/a.dart', absolutePath: '/a'),
      'lib/b.dart': FileNode(relativePath: 'lib/b.dart', absolutePath: '/b'),
      'lib/c.dart': FileNode(relativePath: 'lib/c.dart', absolutePath: '/c'),
    },
    edges: [
      GraphEdge(from: 'lib/a.dart', to: 'lib/b.dart', line: 3),
      GraphEdge(from: 'lib/b.dart', to: 'lib/a.dart', line: 5),
      GraphEdge(from: 'lib/c.dart', to: 'lib/a.dart', line: 2),
    ],
  );
  const cycle = Cycle(
    files: ['lib/a.dart', 'lib/b.dart'],
    exampleChain: ['lib/a.dart', 'lib/b.dart', 'lib/a.dart'],
  );
  const violation = LayerViolation(
    sourceFile: 'lib/c.dart',
    targetFile: 'lib/a.dart',
    sourceLayer: 'domain',
    targetLayer: 'ui',
    line: 2,
  );
  const packageViolation = PackageViolation(
    sourceFile: 'lib/c.dart',
    uri: 'package:flutter/material.dart',
    package: 'flutter',
    pattern: 'flutter',
    layer: 'domain',
    line: 1,
  );

  group('workspace rules in reports', () {
    const wv = WorkspaceViolation(
      sourceFile: 'apps/mobile/lib/m.dart',
      targetFile: 'packages/ui/lib/ui.dart',
      sourcePackage: 'mobile',
      targetPackage: 'ui',
      selector: 'apps/*',
      allowed: ['packages/core'],
      line: 3,
    );

    test('SARIF', () {
      final log = jsonDecode(
        SarifExporter.export(
          result: result,
          cycles: const [],
          workspaceViolations: [wv],
        ),
      );
      final hit = log['runs'][0]['results'][0];
      expect(hit['ruleId'], 'workspace-dependency');
      expect(hit['locations'][0]['physicalLocation']['region']['startLine'], 3);
    });

    test('Markdown', () {
      final md = MarkdownExporter.export(
        result: result,
        cycles: const [],
        workspaceViolations: [wv],
      );
      expect(md, contains('### New workspace rule violations'));
      expect(md, contains('| Workspace rule violations | 1 | 1 |'));
    });

    test('JSON', () {
      final json = jsonDecode(
        JsonExporter.export(
          result: result,
          cycles: const [],
          workspaceViolations: [wv.toJson()],
        ),
      );
      expect(json['workspaceViolations'][0]['targetPackage'], 'ui');
    });
  });

  group('metric limits in reports', () {
    const mv = MetricViolation(
      file: 'lib/a.dart',
      metric: 'fan_out',
      value: 25,
      limit: 20,
    );
    const hot = FileMetrics(file: 'lib/a.dart', fanIn: 3, fanOut: 25);

    test('SARIF', () {
      final log = jsonDecode(
        SarifExporter.export(
          result: result,
          cycles: const [],
          metricViolations: [mv],
        ),
      );
      expect(log['runs'][0]['results'][0]['ruleId'], 'metric-limit');
    });

    test('Markdown lists violations and hotspots', () {
      final md = MarkdownExporter.export(
        result: result,
        cycles: const [],
        metricViolations: [mv],
        hotspots: [hot],
      );
      expect(md, contains('### New metric limit violations'));
      expect(md, contains('| Metric limit violations | 1 | 1 |'));
      expect(md, contains('<summary>Most coupled files</summary>'));
      expect(md, contains('| `lib/a.dart` | 3 | 25 | 0.89 |'));
    });

    test('JSON', () {
      final json = jsonDecode(
        JsonExporter.export(
          result: result,
          cycles: const [],
          metricViolations: [mv.toJson()],
          hotspots: [hot.toJson()],
        ),
      );
      expect(json['metricViolations'][0]['value'], 25);
      expect(json['hotspots'][0]['fanOut'], 25);
    });
  });

  group('forbidden packages in reports', () {
    test('SARIF reports them under forbidden-package at the import line', () {
      final log = jsonDecode(
        SarifExporter.export(
          result: result,
          cycles: const [],
          packageViolations: [packageViolation],
        ),
      );
      final run = log['runs'][0];
      final hit = (run['results'] as List).single;
      expect(hit['ruleId'], 'forbidden-package');
      expect(hit['level'], 'error');
      expect(hit['locations'][0]['physicalLocation']['region']['startLine'], 1);
      expect(
        (run['tool']['driver']['rules'] as List).map((r) => r['id']),
        contains('forbidden-package'),
      );
    });

    test('Markdown lists new ones and counts them', () {
      final md = MarkdownExporter.export(
        result: result,
        cycles: const [],
        packageViolations: [packageViolation],
      );
      expect(md, contains('### New forbidden package imports'));
      expect(md, contains('| Forbidden package imports | 1 | 1 |'));
      expect(md, contains('`lib/c.dart:1`'));
    });

    test('JSON includes them', () {
      final json = jsonDecode(
        JsonExporter.export(
          result: result,
          cycles: const [],
          packageViolations: [packageViolation.toJson()],
        ),
      );
      expect(json['packageViolations'][0]['package'], 'flutter');
    });
  });

  group('SarifExporter', () {
    Map<String, dynamic> export({BaselineComparison? baseline}) =>
        jsonDecode(
              SarifExporter.export(
                result: result,
                cycles: [cycle],
                layerViolations: [violation],
                baseline: baseline,
                failOnLayerViolation: false,
                uriPrefix: 'packages/app/',
              ),
            )
            as Map<String, dynamic>;

    test('emits a SARIF 2.1.0 log with one result per problem', () {
      final log = export();
      expect(log['version'], equals('2.1.0'));
      final run = (log['runs'] as List).single as Map;
      expect(run['tool']['driver']['version'], equals(packageVersion));
      final results = (run['results'] as List).cast<Map>();
      expect(
        results.map((r) => r['ruleId']),
        equals(['layer-violation', 'circular-dependency']),
      );
      expect(results.every((r) => !r.containsKey('baselineState')), isTrue);
    });

    test('points at the offending import line under the uri prefix', () {
      final results = (export()['runs'][0]['results'] as List).cast<Map>();
      final layer = results[0];
      expect(layer['level'], equals('warning'));
      final physical = layer['locations'][0]['physicalLocation'];
      expect(
        physical['artifactLocation']['uri'],
        equals('packages/app/lib/c.dart'),
      );
      expect(physical['region']['startLine'], equals(2));

      final cyc = results[1];
      expect(cyc['level'], equals('error'));
      expect(cyc['locations'][0]['physicalLocation']['region']['startLine'], 3);
      expect(
        cyc['relatedLocations'][0]['physicalLocation']['region']['startLine'],
        5,
      );
    });

    test('marks baseline state when a baseline is in use', () {
      final comparison = const BaselineComparison(
        newCycles: [],
        knownCycles: [cycle],
        newViolations: [violation],
        knownViolations: [],
      );
      final results =
          (export(baseline: comparison)['runs'][0]['results'] as List)
              .cast<Map>();
      expect(results[0]['baselineState'], equals('new'));
      expect(results[1]['baselineState'], equals('unchanged'));
    });
  });

  group('MarkdownExporter', () {
    test('lists new problems and embeds the cycle graph', () {
      final md = MarkdownExporter.export(
        result: result,
        cycles: [cycle],
        layerViolations: [violation],
      );
      expect(md, startsWith(MarkdownExporter.marker));
      expect(md, contains('❌ **Architecture problems found.**'));
      expect(md, contains('### New layer violations'));
      expect(md, contains('`lib/c.dart:2` (**domain**) imports `lib/a.dart`'));
      expect(md, contains('### New circular dependencies'));
      expect(md, contains('```mermaid'));
    });

    test('never writes #<number>, which GitHub links to issues and PRs', () {
      final md = MarkdownExporter.export(
        result: result,
        cycles: [
          Cycle(
            files: cycle.files,
            exampleChain: cycle.exampleChain,
            scc: SccComponent(
              id: 1,
              files: cycle.files,
              exampleChain: cycle.exampleChain,
              internalEdgesCount: 2,
              averageFanIn: 1,
              averageFanOut: 1,
              instability: 0.5,
              density: 1,
              hubFile: 'lib/a.dart',
            ),
          ),
        ],
        oversizedCycles: const [],
      );
      expect(md, contains('**Cycle 1**'));
      expect(md, isNot(matches(RegExp(r'#\d'))));
    });

    test('reports success when every problem is in the baseline', () {
      final md = MarkdownExporter.export(
        result: result,
        cycles: [cycle],
        layerViolations: [violation],
        baseline: const BaselineComparison(
          newCycles: [],
          knownCycles: [cycle],
          newViolations: [],
          knownViolations: [violation],
          fixedViolationCount: 1,
        ),
      );
      expect(md, contains('✅ **No new architecture problems.**'));
      expect(md, isNot(contains('### New')));
      expect(md, contains('--update-baseline'));
    });

    test('reports a clean project', () {
      final md = MarkdownExporter.export(result: result, cycles: const []);
      expect(
        md,
        contains('✅ **No circular dependencies or layer violations.**'),
      );
      expect(md, isNot(contains('mermaid')));
    });
  });

  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(packageVersion, equals(version));
  });
}
