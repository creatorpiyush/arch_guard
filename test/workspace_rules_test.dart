import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  void write(String path, String content) {
    final file = File(p.join(dir.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('arch_guard_wsr_');
    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n  - apps/mobile\n  - packages/core\n  - packages/ui\n',
    );
    write('apps/mobile/pubspec.yaml', 'name: mobile\nresolution: workspace\n');
    write('packages/core/pubspec.yaml', 'name: core\nresolution: workspace\n');
    write('packages/ui/pubspec.yaml', 'name: ui\nresolution: workspace\n');
    write('packages/core/lib/core.dart', '');
    write('packages/ui/lib/ui.dart', "import 'package:core/core.dart';\n");
    write('apps/mobile/lib/main.dart', "import 'package:ui/ui.dart';\n");
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('scan records workspace members', () async {
    final result = await ProjectScanner(rootPath: dir.path).scan();
    expect(result.packages.map((m) => m.packagePath), [
      'apps/mobile',
      'packages/core',
      'packages/ui',
    ]);
  });

  test('config parses workspace_rules in order and drops bad globs', () {
    final config = ArchGuardConfig.parse('''
workspace_rules:
  "apps/*":
    allowed: ["packages/*"]
  core:
    allowed: []
  "packages/[x":
    allowed: ["packages/{y"]
''', rootPath: dir.path);
    expect(config.workspaceRules.keys, ['apps/*', 'core']);
    expect(config.workspaceRules['apps/*'], ['packages/*']);
    expect(config.workspaceRules['core'], isEmpty);
    expect(
      config.warnings.where((w) => w.contains('is not a valid glob')),
      hasLength(1),
    );
  });
}
