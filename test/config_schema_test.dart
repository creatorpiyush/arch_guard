import 'dart:convert';
import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

/// Pins docs/arch_guard.schema.json to the keys the config parser knows, so a
/// new config key can't ship without its schema entry.
void main() {
  final schema =
      jsonDecode(File('docs/arch_guard.schema.json').readAsStringSync())
          as Map<String, dynamic>;
  final props = schema['properties'] as Map<String, dynamic>;

  Set<String> keysOf(Map<String, dynamic> node) =>
      (node['properties'] as Map<String, dynamic>).keys.toSet();

  test('top-level properties match ArchGuardConfig.knownKeys', () {
    expect(props.keys.toSet(), equals(ArchGuardConfig.knownKeys));
    expect(schema['additionalProperties'], isFalse);
  });

  test('metrics properties match ArchGuardConfig.metricsKeys', () {
    expect(
      keysOf(props['metrics'] as Map<String, dynamic>),
      equals(ArchGuardConfig.metricsKeys),
    );
  });

  test('unused_files properties match ArchGuardConfig.unusedFilesKeys', () {
    final variants = (props['unused_files'] as Map)['oneOf'] as List;
    final object = variants.cast<Map<String, dynamic>>().singleWhere(
      (v) => v['type'] == 'object',
    );
    expect(keysOf(object), equals(ArchGuardConfig.unusedFilesKeys));
  });

  test('preset enum matches LayerPresets.names', () {
    expect(
      ((props['preset'] as Map)['enum'] as List).toSet(),
      equals(LayerPresets.names.toSet()),
    );
  });

  test('every property has a description', () {
    for (final entry in props.entries) {
      expect(
        (entry.value as Map)['description'],
        isA<String>(),
        reason: entry.key,
      );
    }
  });

  test('schemaUrl points at the published schema', () {
    expect(schema[r'$id'], equals(ArchGuardConfig.schemaUrl));
  });
}
