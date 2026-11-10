import 'package:arch_guard/arch_guard.dart';
import 'package:glob/glob.dart';
import 'package:test/test.dart';

void main() {
  test('fast exclude matching agrees with Glob', () {
    const paths = [
      'lib/a.dart',
      'lib/a.g.dart',
      'a.g.dart',
      'lib/.g.dart',
      'lib/x.g.dart.bak',
      'lib/g.dart',
      'lib/src/model.freezed.dart',
      'lib/build/x.dart',
      'build/x.dart',
      'lib/builder/x.dart',
      'lib/mybuild/x.dart',
      'lib/build',
      'lib/stub/a.dart',
      'lib/stubs/deep/a.dart',
      'packages/a/.dart_tool/x.dart',
      'lib/a.mocks.dart',
      'lib/a.template.dart',
    ];
    const patterns = [
      ...defaultExcludePatterns,
      '**/*.pb.dart',
      '**/generated/**',
      'lib/legacy/**',
      '**/*_{a,b}.dart',
    ];
    for (final pattern in patterns) {
      final fast = ProjectScanner.excludeMatcher(pattern);
      final glob = Glob(pattern);
      for (final path in paths) {
        expect(fast(path), glob.matches(path), reason: '$pattern on $path');
      }
    }
  });
}
