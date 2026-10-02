import 'package:arch_guard/src/scanner/import_reader.dart';
import 'package:test/test.dart';

void main() {
  group('ImportReader.extractDirectives', () {
    test('extracts single and double quoted imports', () {
      const code = '''
        import 'package:foo/a.dart';
        import "package:foo/b.dart";
      ''';
      final directives = ImportReader.extractDirectives(code);
      expect(
        directives.map((d) => d.uri),
        containsAll(['package:foo/a.dart', 'package:foo/b.dart']),
      );
    });

    test('extracts exports as well as imports', () {
      const code = '''
        import 'src/a.dart';
        export 'src/b.dart';
      ''';
      final directives = ImportReader.extractDirectives(code);
      expect(directives.length, equals(2));
      expect(directives[0].type, equals('import'));
      expect(directives[0].uri, equals('src/a.dart'));
      expect(directives[1].type, equals('export'));
      expect(directives[1].uri, equals('src/b.dart'));
    });

    test('handles multi-line import statements', () {
      const code = '''
        import
          'package:my_app/services/auth.dart'
          show AuthService;
      ''';
      final directives = ImportReader.extractDirectives(code);
      expect(directives.length, equals(1));
      expect(directives[0].uri, equals('package:my_app/services/auth.dart'));
    });

    test('extracts all URIs from conditional imports', () {
      const code = '''
        import 'src/platform_stub.dart'
            if (dart.library.html) 'src/platform_web.dart'
            if (dart.library.io) 'src/platform_io.dart';
      ''';
      final directives = ImportReader.extractDirectives(code);
      expect(
        directives.map((d) => d.uri),
        containsAll([
          'src/platform_stub.dart',
          'src/platform_web.dart',
          'src/platform_io.dart',
        ]),
      );
      expect(directives.every((d) => d.type == 'import'), isTrue);
    });

    test('ignores comments and part-of, extracts part URIs', () {
      const code = '''
        // import 'package:ignored/ignored.dart';
        part 'a.g.dart';
        part of 'b.dart';
        import 'package:valid/valid.dart'; // inline comment
      ''';
      final directives = ImportReader.extractDirectives(code);
      expect(directives.length, equals(2));
      expect(directives[0].uri, equals('a.g.dart'));
      expect(directives[0].type, equals('part'));
      expect(directives[1].uri, equals('package:valid/valid.dart'));
      expect(directives[1].type, equals('import'));
    });

    test('ignores part of with a library name', () {
      const code = '''
        part of my.library;
        class A {}
      ''';
      expect(ImportReader.extractDirectives(code), isEmpty);
    });

    test('keeps URIs that contain //', () {
      const code = '''
        import 'http://example.com/a.dart';
        import 'src//b.dart';
      ''';
      expect(
        ImportReader.extractDirectives(code).map((d) => d.uri),
        equals(['http://example.com/a.dart', 'src//b.dart']),
      );
    });

    test('a /* inside a line comment does not swallow later imports', () {
      const code = '''
        import 'a.dart'; // see lib/*
        import 'b.dart';
        /* real block comment */
        import 'c.dart';
      ''';
      expect(
        ImportReader.extractDirectives(code).map((d) => d.uri),
        equals(['a.dart', 'b.dart', 'c.dart']),
      );
    });

    test('handles nested block comments', () {
      const code = '''
        /* outer /* inner */ import 'hidden.dart'; */
        import 'visible.dart';
      ''';
      expect(
        ImportReader.extractDirectives(code).map((d) => d.uri),
        equals(['visible.dart']),
      );
    });

    test('ignores import-like text after the first declaration', () {
      const code =
          "import 'real.dart';\n"
          "const template = '''\n"
          "import 'fake.dart';\n"
          "''';\n";
      expect(
        ImportReader.extractDirectives(code).map((d) => d.uri),
        equals(['real.dart']),
      );
    });

    test('skips library directives, annotations and script tags', () {
      const code = '''#!/usr/bin/env dart
@TestOn('vm')
@Tags(['slow', 'io'])
library my_lib;

import 'a.dart' deferred as a;
@Deprecated('x') import "b.dart" show B hide C;
export r'c.dart';
''';
      final directives = ImportReader.extractDirectives(code);
      expect(
        directives.map((d) => (d.uri, d.type)),
        equals([
          ('a.dart', 'import'),
          ('b.dart', 'import'),
          ('c.dart', 'export'),
        ]),
      );
    });

    test('does not treat condition values as URIs', () {
      const code = '''
        import 'stub.dart' if (dart.library.io == 'true') 'io.dart';
      ''';
      expect(
        ImportReader.extractDirectives(code).map((d) => d.uri),
        equals(['stub.dart', 'io.dart']),
      );
    });
  });

  group('ImportReader.resolveUri', () {
    test('drops dart: imports', () {
      final res = ImportReader.resolveUri(
        uri: 'dart:async',
        packageName: 'my_app',
        importingFileRelativePath: 'lib/main.dart',
      );
      expect(res, isNull);
    });

    test('drops external package imports', () {
      final res = ImportReader.resolveUri(
        uri: 'package:flutter/material.dart',
        packageName: 'my_app',
        importingFileRelativePath: 'lib/main.dart',
      );
      expect(res, isNull);
    });

    test('resolves self-package imports', () {
      final res = ImportReader.resolveUri(
        uri: 'package:my_app/services/auth.dart',
        packageName: 'my_app',
        importingFileRelativePath: 'lib/main.dart',
      );
      expect(res, equals('lib/services/auth.dart'));
    });

    test('resolves relative imports', () {
      final res = ImportReader.resolveUri(
        uri: '../models/user.dart',
        packageName: 'my_app',
        importingFileRelativePath: 'lib/services/auth.dart',
      );
      expect(res, equals('lib/models/user.dart'));
    });
  });
}
