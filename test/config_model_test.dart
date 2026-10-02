import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ArchGuardConfig', () {
    test('default configuration provides empty layers and rules', () {
      const config = ArchGuardConfig();
      expect(config.layers, isEmpty);
      expect(config.ignorePatterns, isEmpty);
      expect(config.failOnLayerViolation, isTrue);
    });

    test('LayerDefinition correctly parses YAML map entries', () {
      final layer = LayerDefinition.fromYaml('domain', {
        'patterns': ['lib/domain/**'],
        'allowed_imports': ['domain'],
      });

      expect(layer.name, equals('domain'));
      expect(layer.patterns, contains('lib/domain/**'));
      expect(layer.allowedImports, contains('domain'));
    });

    group('load', () {
      late Directory root;

      setUp(() {
        root = Directory.systemTemp.createTempSync('arch_guard_cfg_');
      });

      tearDown(() {
        root.deleteSync(recursive: true);
      });

      void write(String name, String content) =>
          File(p.join(root.path, name)).writeAsStringSync(content);

      test('parses a valid arch_guard.yaml without warnings', () {
        write('arch_guard.yaml', '''
ignore: ["**/gen/**"]
max_scc_size: 4
fail_on_layer_violation: false
layers:
  domain:
    patterns: ["lib/domain/**"]
    allowed_imports: [domain]
''');
        final config = ArchGuardConfig.load(root.path);
        expect(config.warnings, isEmpty);
        expect(config.ignorePatterns, equals(['**/gen/**']));
        expect(config.maxSccSize, equals(4));
        expect(config.failOnLayerViolation, isFalse);
        expect(config.layers.keys, equals(['domain']));
        expect(
          config.sourcePath,
          equals(p.join(p.canonicalize(root.path), 'arch_guard.yaml')),
        );
      });

      test('warns instead of failing silently on invalid YAML', () {
        write('arch_guard.yaml', 'layers: [unclosed');
        final config = ArchGuardConfig.load(root.path);
        expect(config.layers, isEmpty);
        expect(config.warnings.single, contains('could not be parsed'));
      });

      test('warns on unknown keys and wrongly typed values', () {
        write('arch_guard.yaml', '''
layer: {}
ignore: "**/*.g.dart"
max_scc_size: big
fail_on_layer_violation: "no"
layers:
  domain:
    patterns: lib/domain/**
    allowed_imports: [domian]
''');
        final config = ArchGuardConfig.load(root.path);
        final all = config.warnings.join('\n');
        expect(all, contains('unknown key `layer`'));
        expect(all, contains('`ignore` must be a list'));
        expect(all, contains('`max_scc_size` must be a positive integer'));
        expect(
          all,
          contains('`fail_on_layer_violation` must be true or false'),
        );
        expect(all, contains('`patterns` must be a list'));
        expect(all, contains('unknown layer `domian`'));
        expect(config.failOnLayerViolation, isTrue);
        expect(config.maxSccSize, isNull);
      });

      test('reads legacy dep_graph.yaml with a deprecation warning', () {
        write('dep_graph.yaml', 'max_scc_size: 2\n');
        final config = ArchGuardConfig.load(root.path);
        expect(config.maxSccSize, equals(2));
        expect(config.warnings.single, contains('deprecated'));
      });

      test('reads the arch_guard: section of pubspec.yaml', () {
        write('pubspec.yaml', 'name: demo\narch_guard:\n  max_scc_size: 3\n');
        final config = ArchGuardConfig.load(root.path);
        expect(config.maxSccSize, equals(3));
        expect(config.warnings, isEmpty);
      });
    });
  });
}
