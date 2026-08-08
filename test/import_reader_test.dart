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

    test('ignores comments and part directives', () {
      const code = '''
        // import 'package:ignored/ignored.dart';
        part 'a.g.dart';
        part of 'b.dart';
        import 'package:valid/valid.dart'; // inline comment
      ''';
      final directives = ImportReader.extractDirectives(code);
      expect(directives.length, equals(1));
      expect(directives[0].uri, equals('package:valid/valid.dart'));
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
