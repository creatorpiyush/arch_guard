import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  group('LayerValidator', () {
    test('detects layer boundary violations', () {
      const config = DepGraphConfig(
        layers: {
          'domain': LayerDefinition(
            name: 'domain',
            patterns: ['lib/domain/**'],
            allowedImports: ['domain'], // Domain can only import domain
          ),
          'presentation': LayerDefinition(
            name: 'presentation',
            patterns: ['lib/presentation/**'],
            allowedImports: ['presentation', 'domain'],
          ),
        },
      );

      final result = const ScanResult(
        packageName: 'clean_app',
        files: {
          'lib/domain/usecase.dart': FileNode(
            relativePath: 'lib/domain/usecase.dart',
            absolutePath: '/abs/lib/domain/usecase.dart',
          ),
          'lib/presentation/widget.dart': FileNode(
            relativePath: 'lib/presentation/widget.dart',
            absolutePath: '/abs/lib/presentation/widget.dart',
          ),
        },
        edges: [
          // Violation: domain importing presentation
          GraphEdge(
            from: 'lib/domain/usecase.dart',
            to: 'lib/presentation/widget.dart',
          ),
        ],
      );

      final violations = LayerValidator.validate(
        result: result,
        config: config,
      );
      expect(violations.length, equals(1));
      expect(violations.first.sourceLayer, equals('domain'));
      expect(violations.first.targetLayer, equals('presentation'));
    });
  });
}
