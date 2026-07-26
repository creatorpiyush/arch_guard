import 'package:dep_graph_visualizer/src/cli/run.dart';
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
