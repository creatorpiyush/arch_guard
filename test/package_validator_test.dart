import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

PackageImport _import(String file, String uri, {int? line}) => PackageImport(
  file: file,
  uri: uri,
  package: PackageImport.packageOf(uri)!,
  line: line,
);

ScanResult _scan(List<PackageImport> imports) => ScanResult(
  packageName: 'app',
  files: const {},
  edges: const [],
  packageImports: imports,
);

void main() {
  const config = ArchGuardConfig(
    forbiddenPackages: ['dart:mirrors'],
    layers: {
      'domain': LayerDefinition(
        name: 'domain',
        patterns: ['lib/domain/**'],
        forbiddenPackages: ['flutter', 'firebase_*', 'dart:ui'],
      ),
      'data': LayerDefinition(name: 'data', patterns: ['lib/data/**']),
    },
  );

  List<PackageViolation> validate(List<PackageImport> imports) =>
      PackageValidator.validate(result: _scan(imports), config: config);

  group('PackageValidator', () {
    test('reports layer rules only inside that layer', () {
      final v = validate([
        _import(
          'lib/domain/user.dart',
          'package:flutter/material.dart',
          line: 3,
        ),
        _import('lib/data/api.dart', 'package:flutter/material.dart'),
      ]);
      expect(v, hasLength(1));
      expect(v.single.sourceFile, 'lib/domain/user.dart');
      expect(v.single.package, 'flutter');
      expect(v.single.pattern, 'flutter');
      expect(v.single.layer, 'domain');
      expect(v.single.line, 3);
      expect(
        v.single.rule,
        contains('Layer `domain` may not import `flutter`'),
      );
    });

    test('matches globs and dart: libraries, and only whole names', () {
      final v = validate([
        _import(
          'lib/domain/a.dart',
          'package:firebase_auth/firebase_auth.dart',
        ),
        _import('lib/domain/a.dart', 'dart:ui'),
        _import('lib/domain/a.dart', 'package:flutter_bloc/flutter_bloc.dart'),
      ]);
      expect(v.map((e) => e.package), ['firebase_auth', 'dart:ui']);
      expect(v.first.pattern, 'firebase_*');
    });

    test('project-wide entries apply to every file, inside layers or not', () {
      final v = validate([
        _import('lib/main.dart', 'dart:mirrors'),
        _import('lib/domain/a.dart', 'dart:mirrors'),
      ]);
      expect(v, hasLength(2));
      expect(v.every((e) => e.layer == null), isTrue);
      expect(
        v.first.rule,
        contains('`dart:mirrors` is forbidden in this project'),
      );
    });

    test('works for workspace-prefixed paths', () {
      final v = validate([
        _import(
          'packages/auth/lib/domain/a.dart',
          'package:flutter/widgets.dart',
        ),
      ]);
      expect(v.single.layer, 'domain');
    });

    test('no rules, no violations', () {
      expect(
        PackageValidator.validate(
          result: _scan([
            _import('lib/a.dart', 'package:flutter/material.dart'),
          ]),
          config: const ArchGuardConfig(),
        ),
        isEmpty,
      );
    });

    test('checker ignores relative URIs', () {
      final check = PackageValidator.checker(config);
      expect(check('lib/domain/a.dart', '../data/repo.dart'), isNull);
      expect(
        check('lib/domain/a.dart', 'package:flutter/material.dart'),
        isNotNull,
      );
    });
  });
}
