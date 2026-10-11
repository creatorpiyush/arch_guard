import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:arch_guard/src/cli/init_command.dart';
import 'package:arch_guard/src/cli/run.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File config;

  setUp(() {
    root = Directory.systemTemp.createTempSync('arch_guard_init_');
    config = File(p.join(root.path, 'arch_guard.yaml'));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
    for (final layer in ['domain', 'data', 'presentation']) {
      Directory(p.join(root.path, 'lib', layer)).createSync(recursive: true);
    }
    File(
      p.join(root.path, 'lib', 'domain', 'user.dart'),
    ).writeAsStringSync("import '../data/repo.dart';\n");
    File(p.join(root.path, 'lib', 'data', 'repo.dart')).writeAsStringSync('');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('writes a config for the detected preset', () async {
    expect(await runCli(['init', root.path]), equals(0));
    final yaml = config.readAsStringSync();
    expect(yaml, contains('preset: clean_architecture'));
    expect(yaml, contains('#   domain:'));

    final loaded = ArchGuardConfig.load(root.path);
    expect(loaded.warnings, isEmpty);
    expect(loaded.preset, equals('clean_architecture'));

    // The generated config immediately catches domain -> data.
    expect(await runCli([root.path, '--no-color']), equals(1));
  });

  test('adds a bloc layer for blocs next to a riverpod layout', () async {
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: app\ndependencies:\n  flutter_riverpod: any\n');
    for (final dir in ['application', 'bloc']) {
      Directory(p.join(root.path, 'lib', dir)).createSync();
    }
    File(p.join(root.path, 'lib', 'domain', 'user.dart')).writeAsStringSync('');
    File(
      p.join(root.path, 'lib', 'bloc', 'auth_bloc.dart'),
    ).writeAsStringSync("import '../presentation/page.dart';\n");
    File(
      p.join(root.path, 'lib', 'presentation', 'page.dart'),
    ).writeAsStringSync("import '../bloc/auth_bloc.dart';\n");

    expect(await runCli(['init', root.path]), equals(0));
    final loaded = ArchGuardConfig.load(root.path);
    expect(loaded.warnings, isEmpty);
    expect(loaded.preset, equals('riverpod'));
    expect(loaded.layers['bloc']!.patterns, equals(['lib/**/bloc/**']));
    expect(
      loaded.layers['bloc']!.allowedImports,
      equals(['bloc', 'application', 'domain', 'data']),
    );
    expect(loaded.layers['presentation']!.allowedImports, contains('bloc'));

    // UI -> bloc is fine; bloc -> UI is the one violation.
    final scan = await ProjectScanner(rootPath: root.path).scan();
    final violations = LayerValidator.validate(result: scan, config: loaded);
    expect(violations, hasLength(1));
    expect(violations.single.sourceLayer, equals('bloc'));
  });

  test('refuses to overwrite without --force', () async {
    config.writeAsStringSync('ignore: []\n');
    expect(await runCli(['init', root.path]), equals(1));
    expect(config.readAsStringSync(), equals('ignore: []\n'));

    expect(await runCli(['init', root.path, '--force']), equals(0));
    expect(config.readAsStringSync(), contains('preset:'));
  });

  test('--dry-run writes nothing and --preset overrides detection', () async {
    expect(
      await runCli(['init', root.path, '--dry-run', '--preset', 'bloc']),
      equals(0),
    );
    expect(config.existsSync(), isFalse);
  });

  test('rejects unknown presets with a usage error', () async {
    expect(await runCli(['init', root.path, '--preset', 'nope']), equals(64));
  });

  test('every generated config parses without warnings', () {
    Directory(
      p.join(root.path, 'lib', 'features', 'auth'),
    ).createSync(recursive: true);
    for (final preset in [null, ...LayerPresets.names]) {
      final yaml = buildInitConfig(
        preset: preset,
        reason: 'test',
        rootPath: root.path,
      );
      final parsed = ArchGuardConfig.parse(yaml, rootPath: root.path);
      expect(parsed.warnings, isEmpty, reason: '$preset');
      expect(parsed.preset, equals(preset));
      expect(parsed.ignorePatterns, contains('**/*.g.dart'));
    }
  });
}
