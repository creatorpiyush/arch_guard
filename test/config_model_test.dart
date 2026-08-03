import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';
import 'package:test/test.dart';

void main() {
  group('DepGraphConfig', () {
    test('default configuration provides empty layers and rules', () {
      const config = DepGraphConfig();
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
  });
}
