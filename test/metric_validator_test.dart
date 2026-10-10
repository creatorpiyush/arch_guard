import 'dart:io';

import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  ArchGuardConfig parse(String yaml) =>
      ArchGuardConfig.parse(yaml, rootPath: Directory.systemTemp.path);

  test('parses metrics and validates against limits', () {
    final config = parse(
      'metrics:\n  max_fan_out: 2\n  max_fan_in: 1\n  hotspots: 3\n',
    );
    expect(config.warnings, isEmpty);
    expect(config.maxFanOut, 2);
    expect(config.hotspotCount, 3);

    final v = MetricValidator.validate(
      metrics: const [
        FileMetrics(file: 'lib/god.dart', fanIn: 0, fanOut: 3),
        FileMetrics(file: 'lib/core.dart', fanIn: 2, fanOut: 0),
        FileMetrics(file: 'lib/ok.dart', fanIn: 1, fanOut: 2),
      ],
      config: config,
    );
    expect(v.map((x) => '${x.file}|${x.metric}|${x.value}|${x.limit}'), [
      'lib/god.dart|fan_out|3|2',
      'lib/core.dart|fan_in|2|1',
    ]);
    expect(v.first.rule, contains('imports 3 files'));
    expect(v.first.rule, contains('max_fan_out: 2'));
  });

  test('defaults and bad values', () {
    expect(parse('{}').hotspotCount, 10);
    expect(parse('{}').hasMetricRules, isFalse);
    final bad = parse(
      'metrics:\n  max_fan_out: -1\n  max_fan_in: x\n  nope: 1\n',
    );
    expect(bad.maxFanOut, isNull);
    expect(bad.maxFanIn, isNull);
    expect(bad.warnings, hasLength(3));
  });
}
