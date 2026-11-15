import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// pub.dev takes 10 pub points when a description is outside 60–180
/// characters, and `dart pub publish --dry-run` does not check it.
void main() {
  for (final path in ['pubspec.yaml', 'arch_guard_lint/pubspec.yaml']) {
    test('$path description fits pub.dev limits', () {
      final yaml = loadYaml(File(path).readAsStringSync()) as Map;
      final description = yaml['description'] as String;
      expect(description.length, inInclusiveRange(60, 180));
    });
  }
}
