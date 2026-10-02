import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  group('LayerValidator', () {
    test('detects layer boundary violations', () {
      const config = ArchGuardConfig(
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

  group('LayerValidator – workspace mode', () {
    test(
      'detects layer violations for workspace-prefixed paths using single-pkg patterns',
      () {
        // In workspace mode, file paths carry the package directory prefix, e.g.
        // `packages/auth_pkg/lib/domain/usecase.dart`.
        // Layer patterns are typically written as `lib/domain/**` (single-pkg style).
        // The validator should match both the full path and the lib-relative suffix.
        const config = ArchGuardConfig(
          layers: {
            'domain': LayerDefinition(
              name: 'domain',
              patterns: ['lib/domain/**'],
              allowedImports: ['domain'],
            ),
            'presentation': LayerDefinition(
              name: 'presentation',
              patterns: ['lib/presentation/**'],
              allowedImports: ['presentation', 'domain'],
            ),
          },
        );

        final result = const ScanResult(
          packageName: 'my_workspace',
          workspacePackageCount: 2,
          files: {
            'packages/auth_pkg/lib/domain/usecase.dart': FileNode(
              relativePath: 'packages/auth_pkg/lib/domain/usecase.dart',
              absolutePath: '/repo/packages/auth_pkg/lib/domain/usecase.dart',
            ),
            'packages/auth_pkg/lib/presentation/widget.dart': FileNode(
              relativePath: 'packages/auth_pkg/lib/presentation/widget.dart',
              absolutePath:
                  '/repo/packages/auth_pkg/lib/presentation/widget.dart',
            ),
          },
          edges: [
            // Violation: domain importing presentation (across workspace paths)
            GraphEdge(
              from: 'packages/auth_pkg/lib/domain/usecase.dart',
              to: 'packages/auth_pkg/lib/presentation/widget.dart',
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
      },
    );
  });

  group('LayerValidator.coverage', () {
    const config = ArchGuardConfig(
      layers: {
        'domain': LayerDefinition(name: 'domain', patterns: ['lib/domain/**']),
        'data': LayerDefinition(name: 'data', patterns: ['lib/dta/**']),
      },
    );

    const result = ScanResult(
      packageName: 'clean_app',
      files: {
        'lib/domain/entity.dart': FileNode(
          relativePath: 'lib/domain/entity.dart',
          absolutePath: '/abs/lib/domain/entity.dart',
        ),
        'lib/data/repo.dart': FileNode(
          relativePath: 'lib/data/repo.dart',
          absolutePath: '/abs/lib/data/repo.dart',
        ),
        'lib/main.dart': FileNode(
          relativePath: 'lib/main.dart',
          absolutePath: '/abs/lib/main.dart',
        ),
      },
      edges: [],
    );

    test('reports layers whose patterns match no files', () {
      final coverage = LayerValidator.coverage(result: result, config: config);
      expect(coverage.emptyLayers, equals(['data']));
    });

    test('reports files that belong to no layer', () {
      final coverage = LayerValidator.coverage(result: result, config: config);
      expect(
        coverage.unassignedFiles,
        equals(['lib/data/repo.dart', 'lib/main.dart']),
      );
    });

    test('is empty when no layers are configured', () {
      final coverage = LayerValidator.coverage(
        result: result,
        config: const ArchGuardConfig(),
      );
      expect(coverage.emptyLayers, isEmpty);
      expect(coverage.unassignedFiles, isEmpty);
    });
  });
}
