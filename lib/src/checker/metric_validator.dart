import '../models/config_model.dart';
import '../models/file_metrics.dart';

/// A file over a `metrics:` limit.
class MetricViolation {
  /// Relative path of the file.
  final String file;

  /// `fan_out` or `fan_in`.
  final String metric;

  /// The file's current value.
  final int value;

  /// The configured limit.
  final int limit;

  /// Creates a violation.
  const MetricViolation({
    required this.file,
    required this.metric,
    required this.value,
    required this.limit,
  });

  /// The broken rule.
  String get rule => metric == 'fan_out'
      ? '`$file` imports $value files (max_fan_out: $limit).'
      : '`$file` is imported by $value files (max_fan_in: $limit).';

  /// How to resolve it.
  String get suggestion => metric == 'fan_out'
      ? 'Split the file by responsibility, or depend on a smaller facade.'
      : 'Split the file so importers depend only on what they use, or raise '
            'max_fan_in if it is a deliberate shared core.';

  /// JSON form used by the JSON exporter and baseline.
  Map<String, dynamic> toJson() => {
    'file': file,
    'metric': metric,
    'value': value,
    'limit': limit,
  };

  @override
  String toString() => '❌ Metric Limit: $file $metric=$value (max $limit)';
}

/// Checks [FileMetrics] against the `metrics:` limits.
class MetricValidator {
  /// One violation per file and exceeded limit, fan-out first.
  static List<MetricViolation> validate({
    required List<FileMetrics> metrics,
    required ArchGuardConfig config,
  }) {
    final maxOut = config.maxFanOut;
    final maxIn = config.maxFanIn;
    return [
      if (maxOut != null)
        for (final m in metrics)
          if (m.fanOut > maxOut)
            MetricViolation(
              file: m.file,
              metric: 'fan_out',
              value: m.fanOut,
              limit: maxOut,
            ),
      if (maxIn != null)
        for (final m in metrics)
          if (m.fanIn > maxIn)
            MetricViolation(
              file: m.file,
              metric: 'fan_in',
              value: m.fanIn,
              limit: maxIn,
            ),
    ];
  }
}
