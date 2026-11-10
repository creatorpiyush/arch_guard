import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

ScanResult _scan(Map<String, String> sources) =>
    ProjectScanner.scanSources(packageName: 'app', sources: sources);

List<ImportStep>? _why(Map<String, String> sources, String from, String to) {
  final result = _scan(sources);
  return ImportPath.find(
    result: result,
    from: ImportPath.matchFiles(result, from),
    to: ImportPath.matchTarget(result, to),
  );
}

void main() {
  test('shortest of two paths is chosen', () {
    final path = _why(
      {
        'lib/a.dart': "import 'b.dart';\nimport 'c.dart';",
        'lib/b.dart': "import 'c.dart';",
        'lib/c.dart': '',
      },
      'lib/a.dart',
      'lib/c.dart',
    )!;
    expect(path, hasLength(1));
    expect(path.single.from, 'lib/a.dart');
    expect(path.single.to, 'lib/c.dart');
    expect(path.single.line, 2);
  });

  test('folder from uses all files under it', () {
    final path = _why(
      {
        'lib/domain/a.dart': '',
        'lib/domain/b.dart': "import '../data/x.dart';",
        'lib/data/x.dart': '',
      },
      'lib/domain/',
      'lib/data',
    )!;
    expect(path.single.from, 'lib/domain/b.dart');
  });

  test('package target ends on the import line', () {
    final path = _why(
      {
        'lib/a.dart': "import 'b.dart';",
        'lib/b.dart': "\nimport 'package:flutter/material.dart';",
      },
      'lib/a.dart',
      'package:flutter',
    )!;
    expect(path, hasLength(2));
    expect(path.last.from, 'lib/b.dart');
    expect(path.last.to, 'package:flutter/material.dart');
    expect(path.last.line, 2);
  });

  test('bare package name resolves when no file matches', () {
    final result = _scan({
      'lib/a.dart': "import 'package:flutter/widgets.dart';",
    });
    final target = ImportPath.matchTarget(result, 'flutter');
    expect(target, isA<PackageTarget>());
    expect((target as PackageTarget).package, 'flutter');
    expect(target.label, 'package:flutter');
  });

  test('dart:io target', () {
    final path = _why(
      {'lib/a.dart': "import 'dart:io';"},
      'lib/a.dart',
      'dart:io',
    )!;
    expect(path.single.to, 'dart:io');
  });

  test('export, part and conditional steps keep type and condition', () {
    final path = _why(
      {
        'lib/a.dart': "export 'b.dart';",
        'lib/b.dart': "part 'c.dart';",
        'lib/c.dart':
            "part of 'b.dart';\n"
            "import 'stub.dart' if (dart.library.io) 'io.dart';",
        'lib/io.dart': '',
        'lib/stub.dart': '',
      },
      'lib/a.dart',
      'lib/io.dart',
    )!;
    expect(path.map((s) => s.type), ['export', 'part', 'import']);
    expect(path.last.condition, 'dart.library.io');
  });

  test('no path returns null', () {
    expect(
      _why(
        {'lib/a.dart': '', 'lib/b.dart': "import 'a.dart';"},
        'lib/a.dart',
        'lib/b.dart',
      ),
      isNull,
    );
  });

  test('from file inside target returns empty path', () {
    expect(_why({'lib/a/x.dart': ''}, 'lib/a/x.dart', 'lib/a'), isEmpty);
  });

  test('ambiguous suffix throws', () {
    final result = _scan({'lib/a/user.dart': '', 'lib/b/user.dart': ''});
    expect(
      () => ImportPath.matchFiles(result, 'user.dart'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          '"user.dart" matches 2 files: lib/a/user.dart, lib/b/user.dart',
        ),
      ),
    );
    expect(
      () => ImportPath.matchTarget(result, 'user.dart'),
      throwsArgumentError,
    );
  });

  test('unknown argument throws', () {
    final result = _scan({'lib/a.dart': ''});
    expect(
      () => ImportPath.matchFiles(result, 'nope'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'no scanned file or folder matches "nope".',
        ),
      ),
    );
  });

  test('backslash argument matches', () {
    final result = _scan({'lib/domain/a.dart': '', 'lib/data/b.dart': ''});
    expect(ImportPath.matchFiles(result, r'lib\domain'), {'lib/domain/a.dart'});
    expect(ImportPath.matchTarget(result, r'lib\domain').label, 'lib/domain/');
  });

  test('package: URI of the scanned package is a file target', () {
    final sources = {
      'lib/a.dart': "import 'package:app/data/c.dart';",
      'lib/data/c.dart': '',
    };
    final path = _why(sources, 'lib/a.dart', 'package:app/data/c.dart')!;
    expect(path.single.to, 'lib/data/c.dart');
    final result = _scan(sources);
    expect(
      ImportPath.matchTarget(result, 'package:app/data').label,
      'lib/data/',
    );
    expect(ImportPath.matchTarget(result, 'package:app').label, 'lib/');
    expect(
      () => ImportPath.matchTarget(result, 'package:app/nope.dart'),
      throwsArgumentError,
    );
  });
}
