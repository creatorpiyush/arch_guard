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
}
