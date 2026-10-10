import 'dart:io';

import 'package:arch_guard/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  void write(String path, String content) {
    final file = File(p.join(project.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('arch_guard_testing_');
    write('pubspec.yaml', 'name: app\n');
    write('arch_guard.yaml', '''
layers:
  domain:
    patterns: ["lib/domain/**"]
  data:
    patterns: ["lib/data/**"]
    allowed_imports: [domain]
''');
    write('lib/data/repo.dart', "import '../domain/user.dart';\n");
    write('lib/domain/user.dart', '');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('passes on a clean project and returns the analysis', () async {
    final a = await expectArchitecture(projectPath: project.path);
    expect(a.scan.files, hasLength(2));
  });

  test('throws a readable exception on violations', () async {
    write('lib/domain/user.dart', "import '../data/repo.dart';\n");
    await expectLater(
      expectArchitecture(projectPath: project.path, failOnCycle: false),
      throwsA(
        isA<ArchitectureViolationException>()
            .having((e) => e.failures, 'failures', hasLength(1))
            .having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('1 architecture problem'),
                contains('lib/domain/user.dart:1'),
                contains('--update-baseline'),
              ),
            ),
      ),
    );
  });

  test('cycles fail unless failOnCycle is false', () async {
    write('lib/domain/user.dart', "import '../data/repo.dart';\n");
    write('arch_guard.yaml', 'fail_on_layer_violation: false\n');
    await expectLater(
      expectArchitecture(projectPath: project.path),
      throwsA(isA<ArchitectureViolationException>()),
    );
    await expectArchitecture(projectPath: project.path, failOnCycle: false);
  });

  test('works with a relative project path', () async {
    final rel = p.relative(project.path);
    await expectArchitecture(projectPath: rel);
  });

  test('a broken baseline file is an error, not a pass', () async {
    write('arch_guard_baseline.json', '{nope');
    await expectLater(
      expectArchitecture(projectPath: project.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('caps the message at 50 problems', () async {
    for (var i = 0; i < 60; i++) {
      write('lib/domain/f$i.dart', "import '../data/repo.dart';\n");
    }
    write('lib/data/repo.dart', '');
    try {
      await expectArchitecture(projectPath: project.path);
      fail('expected an exception');
    } on ArchitectureViolationException catch (e) {
      expect(e.failures, hasLength(60));
      expect(e.toString(), contains('… and 10 more'));
    }
  });
}
