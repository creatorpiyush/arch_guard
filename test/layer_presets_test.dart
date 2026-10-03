import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds a scan result with one edge per `from -> to` pair.
ScanResult _scan(
  List<(String, String)> edges, [
  List<String> extra = const [],
]) {
  final files = {
    for (final path in [
      ...edges.expand((e) => [e.$1, e.$2]),
      ...extra,
    ])
      path: FileNode(relativePath: path, absolutePath: '/abs/$path'),
  };
  return ScanResult(
    packageName: 'app',
    files: files,
    edges: [for (final (from, to) in edges) GraphEdge(from: from, to: to)],
  );
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('arch_guard_preset_'));
  tearDown(() => root.deleteSync(recursive: true));

  ArchGuardConfig parse(String yaml) =>
      ArchGuardConfig.parse(yaml, rootPath: root.path);

  group('clean_architecture preset', () {
    test('matches layer-first and feature-first layouts', () {
      final config = parse('preset: clean_architecture');
      expect(config.preset, equals('clean_architecture'));
      expect(config.warnings, isEmpty);

      final coverage = LayerValidator.coverage(
        result: _scan(const [], [
          'lib/core/util.dart',
          'lib/domain/user.dart',
          'lib/features/auth/data/repo.dart',
          'lib/features/auth/presentation/page.dart',
          'lib/main.dart',
        ]),
        config: config,
      );
      expect(
        coverage.layerFileCounts,
        equals({'core': 1, 'domain': 1, 'data': 1, 'presentation': 1}),
      );
      expect(coverage.unassignedFiles, equals(['lib/main.dart']));
    });

    test('lets presentation use domain but not data', () {
      final violations = LayerValidator.validate(
        result: _scan(const [
          ('lib/presentation/page.dart', 'lib/domain/user.dart'),
          ('lib/presentation/page.dart', 'lib/data/repo.dart'),
          ('lib/domain/user.dart', 'lib/core/util.dart'),
        ]),
        config: parse('preset: clean_architecture'),
      );
      expect(violations, hasLength(1));
      expect(violations.single.targetLayer, equals('data'));
      expect(
        violations.single.allowedImports,
        equals(['core', 'domain', 'presentation']),
      );
    });

    test('layers: overrides only the keys it lists', () {
      final config = parse('''
preset: clean_architecture
layers:
  presentation:
    allowed_imports: [core, domain, presentation, data]
  di:
    patterns: ["lib/di/**"]
    allowed_imports: [core, domain, data, presentation, di]
''');
      expect(config.warnings, isEmpty);
      expect(
        config.layers['presentation']!.patterns,
        equals(['**/presentation/**', '**/ui/**']),
      );
      expect(config.layers['presentation']!.allowedImports, contains('data'));
      expect(config.layers.keys.last, equals('di'));
      expect(config.presetOnlyLayers, equals({'core', 'domain', 'data'}));
    });
  });

  group('other presets', () {
    test('bloc keeps presentation away from repositories', () {
      final violations = LayerValidator.validate(
        result: _scan(const [
          ('lib/counter/view/page.dart', 'lib/counter/bloc/counter_bloc.dart'),
          ('lib/counter/view/page.dart', 'lib/repositories/repo.dart'),
          ('lib/counter/bloc/counter_bloc.dart', 'lib/repositories/repo.dart'),
        ]),
        config: parse('preset: bloc'),
      );
      expect(violations.map((v) => v.targetLayer), equals(['repository']));
    });

    test('riverpod keeps domain free of other layers', () {
      final violations = LayerValidator.validate(
        result: _scan(const [
          ('lib/cart/domain/item.dart', 'lib/cart/data/repo.dart'),
          ('lib/cart/presentation/page.dart', 'lib/cart/data/repo.dart'),
          ('lib/cart/application/service.dart', 'lib/cart/data/repo.dart'),
        ]),
        config: parse('preset: riverpod'),
      );
      expect(violations.map((v) => v.sourceLayer), equals(['domain']));
    });

    test('feature_first isolates features discovered on disk', () {
      for (final f in ['auth', 'cart']) {
        Directory(
          p.join(root.path, 'lib', 'features', f),
        ).createSync(recursive: true);
      }
      final config = parse('preset: feature_first');
      expect(
        config.layers.keys,
        equals(['shared', 'feature_auth', 'feature_cart']),
      );

      final violations = LayerValidator.validate(
        result: _scan(const [
          ('lib/features/auth/a.dart', 'lib/core/k.dart'),
          ('lib/features/auth/a.dart', 'lib/features/cart/c.dart'),
          ('lib/shared/s.dart', 'lib/features/auth/a.dart'),
        ]),
        config: config,
      );
      expect(
        violations.map((v) => '${v.sourceLayer}->${v.targetLayer}'),
        equals(['feature_auth->feature_cart', 'shared->feature_auth']),
      );
    });

    test('feature_first warns when there are no feature folders', () {
      final config = parse('preset: feature_first');
      expect(config.warnings.single, contains('found no feature folders'));
    });

    test('unknown preset is reported and ignored', () {
      final config = parse('preset: hexagonal');
      expect(config.preset, isNull);
      expect(config.layers, isEmpty);
      expect(config.warnings.single, contains('unknown preset `hexagonal`'));
    });
  });

  group('LayoutDetector', () {
    void dirs(List<String> paths) {
      for (final path in paths) {
        Directory(p.join(root.path, path)).createSync(recursive: true);
      }
    }

    void pubspec(String deps) => File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: app\ndependencies:\n$deps');

    test('detects clean architecture inside feature folders', () {
      dirs(['lib/features/auth/domain', 'lib/features/auth/data']);
      expect(
        LayoutDetector.detect(root.path).preset,
        equals('clean_architecture'),
      );
    });

    test('detects riverpod from application/ plus the dependency', () {
      dirs(['lib/src/domain', 'lib/src/data', 'lib/src/application']);
      expect(
        LayoutDetector.detect(root.path).preset,
        equals('clean_architecture'),
      );
      pubspec('  flutter_riverpod: any\n');
      expect(LayoutDetector.detect(root.path).preset, equals('riverpod'));
    });

    test('detects bloc and feature-first layouts', () {
      dirs(['lib/features/login']);
      expect(LayoutDetector.detect(root.path).preset, equals('feature_first'));
      dirs(['lib/features/login/cubit']);
      expect(LayoutDetector.detect(root.path).preset, equals('bloc'));
    });

    test('ignores folders outside lib/ and returns null when nothing fits', () {
      dirs(['test/domain', 'test/data', 'lib/src']);
      final detection = LayoutDetector.detect(root.path);
      expect(detection.preset, isNull);
      expect(detection.reason, contains('no common architecture layout'));
    });
  });

  test('LayerViolation explains the broken rule', () {
    const v = LayerViolation(
      sourceFile: 'lib/presentation/page.dart',
      targetFile: 'lib/data/repo.dart',
      sourceLayer: 'presentation',
      targetLayer: 'data',
      line: 4,
      allowedImports: ['core', 'domain'],
    );
    expect(v.rule, equals('`presentation` may only import `core`, `domain`.'));
    expect(v.suggestion, contains('add `data` to the `allowed_imports`'));
    expect(v.toString(), contains('lib/presentation/page.dart:4'));
    expect(v.toJson()['allowedImports'], equals(['core', 'domain']));
  });
}
