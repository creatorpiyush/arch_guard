import 'package:arch_guard/src/cli/run.dart';
import 'package:test/test.dart';

void main() {
  group('CLI execution', () {
    test('returns exit code 64 for invalid flag', () async {
      final code = await runCli(['--invalid-flag-123']);
      expect(code, equals(64));
    });

    test('returns exit code 2 for non-existent directory', () async {
      final code = await runCli(['non_existent_dir_xyz_123']);
      expect(code, equals(2));
    });

    test('returns exit code 1 when cycles found on sample_project', () async {
      final code = await runCli([
        'example/sample_project',
        '-f',
        'all',
        '-o',
        'build/test_out',
      ]);
      expect(code, equals(1));
    });

    test('returns exit code 0 when --explain passed', () async {
      final code = await runCli([
        'example/sample_project',
        '--explain',
        'lib/services/auth_service.dart',
      ]);
      expect(code, equals(0));
    });

    test('returns exit code 0 for --format json', () async {
      final code = await runCli([
        'example/sample_project',
        '--no-fail-on-cycle',
        '-f',
        'json',
        '-o',
        'build/test_out',
      ]);
      expect(code, equals(0));
    });

    test(
      'returns exit code 0 for --format mermaid with scope cycles',
      () async {
        final code = await runCli([
          'example/sample_project',
          '--no-fail-on-cycle',
          '-f',
          'mermaid',
          '--scope',
          'cycles',
          '-o',
          'build/test_out',
        ]);
        expect(code, equals(0));
      },
    );

    test('returns exit code 0 when --no-fail-on-cycle passed', () async {
      final code = await runCli([
        'example/sample_project',
        '--no-fail-on-cycle',
        '-f',
        'all',
        '-o',
        'build/test_out',
      ]);
      expect(code, equals(0));
    });
  });
}
