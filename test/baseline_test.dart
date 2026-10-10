import 'dart:convert';
import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Cycle _cycle(List<String> files) =>
    Cycle(files: files, exampleChain: [...files, files.first]);

LayerViolation _violation(String from, String to) => LayerViolation(
  sourceFile: from,
  targetFile: to,
  sourceLayer: 'domain',
  targetLayer: 'data',
);

void main() {
  group('Baseline', () {
    final baseline = Baseline.capture(
      cycles: [
        _cycle(['lib/a.dart', 'lib/b.dart', 'lib/c.dart']),
        _cycle(['lib/x.dart', 'lib/y.dart']),
      ],
      layerViolations: [_violation('lib/d.dart', 'lib/e.dart')],
    );

    test('accepts unchanged and shrunken cycles as known', () {
      final comparison = baseline.compare(
        cycles: [
          _cycle(['lib/c.dart', 'lib/a.dart', 'lib/b.dart']),
          _cycle(['lib/x.dart', 'lib/y.dart']),
        ],
        layerViolations: const [],
      );
      expect(comparison.newCycles, isEmpty);
      expect(comparison.knownCycles, hasLength(2));

      final shrunk = baseline.compare(
        cycles: [
          _cycle(['lib/a.dart', 'lib/b.dart']),
        ],
        layerViolations: const [],
      );
      expect(shrunk.newCycles, isEmpty);
      expect(shrunk.fixedCycleCount, equals(1));
    });

    test('reports grown, merged and brand-new cycles as new', () {
      final grown = _cycle([
        'lib/a.dart',
        'lib/b.dart',
        'lib/c.dart',
        'lib/z.dart',
      ]);
      final merged = _cycle(['lib/a.dart', 'lib/x.dart']);
      final fresh = _cycle(['lib/m.dart', 'lib/n.dart']);
      final comparison = baseline.compare(
        cycles: [grown, merged, fresh],
        layerViolations: const [],
      );
      expect(comparison.newCycles, equals([grown, merged, fresh]));
      expect(comparison.isNewCycle(fresh), isTrue);
    });

    test('splits layer violations into known, new and fixed', () {
      final known = _violation('lib/d.dart', 'lib/e.dart');
      final fresh = _violation('lib/d.dart', 'lib/f.dart');
      final comparison = baseline.compare(
        cycles: const [],
        layerViolations: [known, fresh],
      );
      expect(comparison.knownViolations, equals([known]));
      expect(comparison.newViolations, equals([fresh]));
      expect(comparison.fixedViolationCount, equals(0));
      expect(comparison.fixedCycleCount, equals(2));

      final none = baseline.compare(
        cycles: const [],
        layerViolations: const [],
      );
      expect(none.fixedViolationCount, equals(1));
    });

    test('round-trips through a sorted JSON file', () {
      final dir = Directory.systemTemp.createTempSync('arch_guard_baseline_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'nested', 'baseline.json');

      baseline.save(path);
      final json = File(path).readAsStringSync();
      expect(json, contains('"version": 1'));
      expect(json.indexOf('lib/a.dart'), lessThan(json.indexOf('lib/x.dart')));

      final loaded = Baseline.load(path)!;
      expect(loaded.cycles, hasLength(2));
      expect(loaded.layerViolations, equals(baseline.layerViolations));
      expect(
        loaded
            .compare(
              cycles: [
                _cycle(['lib/x.dart', 'lib/y.dart']),
              ],
              layerViolations: [_violation('lib/d.dart', 'lib/e.dart')],
            )
            .newViolations,
        isEmpty,
      );
    });

    test('load returns null for a missing file and throws when invalid', () {
      final dir = Directory.systemTemp.createTempSync('arch_guard_baseline_');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(Baseline.load(p.join(dir.path, 'missing.json')), isNull);

      final bad = File(p.join(dir.path, 'bad.json'))
        ..writeAsStringSync('{"version": 1, "cycles": [{"files": 3}]}');
      expect(() => Baseline.load(bad.path), throwsFormatException);

      final future = File(p.join(dir.path, 'future.json'))
        ..writeAsStringSync('{"version": 2}');
      expect(() => Baseline.load(future.path), throwsFormatException);
    });
  });

  group('Baseline package violations', () {
    PackageViolation pv(String file, String package) => PackageViolation(
      sourceFile: file,
      uri: 'package:$package/$package.dart',
      package: package,
      pattern: package,
      layer: 'domain',
    );

    final baseline = Baseline.capture(
      cycles: const [],
      layerViolations: const [],
      packageViolations: [pv('lib/domain/a.dart', 'flutter')],
    );

    test('splits known, new and fixed', () {
      final c = baseline.compare(
        cycles: const [],
        layerViolations: const [],
        packageViolations: [
          pv('lib/domain/a.dart', 'flutter'),
          pv('lib/domain/b.dart', 'flutter'),
        ],
      );
      expect(c.knownPackageViolations.single.sourceFile, 'lib/domain/a.dart');
      expect(c.newPackageViolations.single.sourceFile, 'lib/domain/b.dart');
      expect(c.fixedPackageViolationCount, 0);

      final fixed = baseline.compare(
        cycles: const [],
        layerViolations: const [],
      );
      expect(fixed.fixedPackageViolationCount, 1);
    });

    test('round-trips through JSON', () {
      final again = Baseline.fromJson(
        jsonDecode(jsonEncode(baseline.toJson())),
      );
      expect(again.packageViolations, baseline.packageViolations);
    });

    test('loads a 1.4 baseline without packageViolations', () {
      final old = Baseline.fromJson({
        'version': 1,
        'cycles': [],
        'layerViolations': [],
      });
      final c = old.compare(
        cycles: const [],
        layerViolations: const [],
        packageViolations: [pv('lib/domain/a.dart', 'flutter')],
      );
      expect(c.newPackageViolations, hasLength(1));
    });
  });

  group('Baseline metric ratchet', () {
    MetricViolation mv(int value) => MetricViolation(
      file: 'lib/god.dart',
      metric: 'fan_out',
      value: value,
      limit: 20,
    );
    final baseline = Baseline.capture(
      cycles: const [],
      layerViolations: const [],
      metricViolations: [mv(25)],
    );

    BaselineComparison cmp(int value) => baseline.compare(
      cycles: const [],
      layerViolations: const [],
      metricViolations: [mv(value)],
    );

    test('same or lower is known; higher is new', () {
      expect(cmp(25).newMetricViolations, isEmpty);
      expect(cmp(24).knownMetricViolations, hasLength(1));
      expect(cmp(26).newMetricViolations, hasLength(1));
    });

    test('round-trips and old files load', () {
      final again = Baseline.fromJson(
        jsonDecode(jsonEncode(baseline.toJson())),
      );
      expect(again.metricViolations, {'lib/god.dart|fan_out': 25});
      expect(Baseline.fromJson({'version': 1}).metricViolations, isEmpty);
    });

    test('fixed when the file is back under the limit', () {
      final c = baseline.compare(cycles: const [], layerViolations: const []);
      expect(c.fixedMetricViolationCount, 1);
      expect(cmp(26).fixedMetricViolationCount, 0);
    });
  });

  group('Baseline workspace violations', () {
    WorkspaceViolation wv(String from) => WorkspaceViolation(
      sourceFile: from,
      targetFile: 'packages/a/lib/a.dart',
      sourcePackage: 'core',
      targetPackage: 'a',
      selector: 'core',
    );
    final baseline = Baseline.capture(
      cycles: const [],
      layerViolations: const [],
      workspaceViolations: [wv('packages/core/lib/c.dart')],
    );

    test('known, new, round-trip, old files', () {
      final c = baseline.compare(
        cycles: const [],
        layerViolations: const [],
        workspaceViolations: [
          wv('packages/core/lib/c.dart'),
          wv('packages/core/lib/d.dart'),
        ],
      );
      expect(c.knownWorkspaceViolations, hasLength(1));
      expect(
        c.newWorkspaceViolations.single.sourceFile,
        'packages/core/lib/d.dart',
      );
      expect(
        c.isNewWorkspaceViolation(c.newWorkspaceViolations.single),
        isTrue,
      );
      expect(
        Baseline.fromJson(
          jsonDecode(jsonEncode(baseline.toJson())),
        ).workspaceViolations,
        baseline.workspaceViolations,
      );
      expect(Baseline.fromJson({'version': 1}).workspaceViolations, isEmpty);
      expect(
        baseline
            .compare(cycles: const [], layerViolations: const [])
            .fixedWorkspaceViolationCount,
        1,
      );
    });
  });
}
