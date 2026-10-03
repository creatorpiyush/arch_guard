import 'dart:convert';
import 'dart:io';

import '../checker/layer_validator.dart';
import '../models/cycle.dart';

/// Default baseline file name, resolved relative to the scanned project.
const defaultBaselineFileName = 'arch_guard_baseline.json';

/// A snapshot of known architecture problems that should not fail a run.
///
/// Lets legacy projects adopt arch_guard without fixing everything first:
/// record today's cycles and layer violations once, then fail only on new ones.
class Baseline {
  /// File sets of the circular dependency groups (SCCs) known at capture time.
  final List<Set<String>> cycles;

  /// Known layer violations, keyed by `sourceFile -> targetFile`.
  final Set<String> layerViolations;

  /// Creates a baseline holding [cycles] and [layerViolations].
  const Baseline({this.cycles = const [], this.layerViolations = const {}});

  /// Captures the current [cycles] and [layerViolations] as a baseline.
  factory Baseline.capture({
    required List<Cycle> cycles,
    required List<LayerViolation> layerViolations,
  }) => Baseline(
    cycles: cycles.map((c) => c.files.toSet()).toList(),
    layerViolations: layerViolations.map(violationKey).toSet(),
  );

  /// Parses a baseline from its JSON form. Throws [FormatException] if invalid.
  factory Baseline.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('expected a JSON object');
    }
    final version = json['version'];
    if (version != 1) {
      throw FormatException('unsupported baseline version: $version');
    }

    final cycles = <Set<String>>[];
    for (final entry in json['cycles'] as List? ?? const []) {
      final files = (entry as Map)['files'] as List;
      cycles.add(files.cast<String>().toSet());
    }

    final violations = <String>{};
    for (final entry in json['layerViolations'] as List? ?? const []) {
      final map = entry as Map;
      violations.add(
        _key(map['sourceFile'] as String, map['targetFile'] as String),
      );
    }

    return Baseline(cycles: cycles, layerViolations: violations);
  }

  /// Loads the baseline at [path], or returns `null` if the file is missing.
  /// Throws [FormatException] if the file exists but cannot be parsed.
  static Baseline? load(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return Baseline.fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException catch (e) {
      throw FormatException('invalid baseline $path: ${e.message}');
    } on TypeError catch (e) {
      throw FormatException('invalid baseline $path: $e');
    }
  }

  /// Serializes with sorted entries so the file diffs cleanly in review.
  Map<String, dynamic> toJson() {
    final sortedCycles = cycles.map((c) => c.toList()..sort()).toList()
      ..sort((a, b) => a.join('\n').compareTo(b.join('\n')));
    final sortedViolations = layerViolations.toList()..sort();
    return {
      'version': 1,
      'cycles': [
        for (final files in sortedCycles) {'files': files},
      ],
      'layerViolations': [
        for (final key in sortedViolations)
          {
            'sourceFile': key.split(_separator).first,
            'targetFile': key.split(_separator).last,
          },
      ],
    };
  }

  /// Writes this baseline to [path] as indented JSON.
  void save(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
    );
  }

  /// Splits current problems into new and already-known ones.
  ///
  /// A cycle is known when all of its files sit inside one baseline cycle, so
  /// a cycle that shrinks stays accepted while one that grows (or merges two
  /// known cycles) counts as new.
  BaselineComparison compare({
    required List<Cycle> cycles,
    required List<LayerViolation> layerViolations,
  }) {
    final newCycles = <Cycle>[];
    final knownCycles = <Cycle>[];
    final matchedBaselineCycles = <int>{};
    for (final cycle in cycles) {
      final index = this.cycles.indexWhere(
        (known) => known.containsAll(cycle.files),
      );
      if (index == -1) {
        newCycles.add(cycle);
      } else {
        knownCycles.add(cycle);
        matchedBaselineCycles.add(index);
      }
    }

    final newViolations = <LayerViolation>[];
    final knownViolations = <LayerViolation>[];
    final seenViolations = <String>{};
    for (final violation in layerViolations) {
      final key = violationKey(violation);
      if (this.layerViolations.contains(key)) {
        knownViolations.add(violation);
        seenViolations.add(key);
      } else {
        newViolations.add(violation);
      }
    }

    return BaselineComparison(
      newCycles: newCycles,
      knownCycles: knownCycles,
      newViolations: newViolations,
      knownViolations: knownViolations,
      fixedCycleCount: this.cycles.length - matchedBaselineCycles.length,
      fixedViolationCount: this.layerViolations
          .difference(seenViolations)
          .length,
    );
  }

  /// Stable identity of a layer violation, independent of layer names and lines.
  static String violationKey(LayerViolation v) =>
      _key(v.sourceFile, v.targetFile);

  static const _separator = ' -> ';

  static String _key(String source, String target) =>
      '$source$_separator$target';
}

/// Current problems split into new ones and ones already in the baseline.
class BaselineComparison {
  /// Cycles that are not in the baseline.
  final List<Cycle> newCycles;

  /// Cycles that the baseline already lists.
  final List<Cycle> knownCycles;

  /// Layer violations that are not in the baseline.
  final List<LayerViolation> newViolations;

  /// Layer violations that the baseline already lists.
  final List<LayerViolation> knownViolations;

  /// Baseline cycles that no longer occur at all.
  final int fixedCycleCount;

  /// Baseline layer violations that no longer occur.
  final int fixedViolationCount;

  /// Creates a comparison from already split problem lists.
  const BaselineComparison({
    required this.newCycles,
    required this.knownCycles,
    required this.newViolations,
    required this.knownViolations,
    this.fixedCycleCount = 0,
    this.fixedViolationCount = 0,
  });

  /// Treats every problem as new (used when there is no baseline).
  factory BaselineComparison.allNew({
    required List<Cycle> cycles,
    required List<LayerViolation> layerViolations,
  }) => BaselineComparison(
    newCycles: cycles,
    knownCycles: const [],
    newViolations: layerViolations,
    knownViolations: const [],
  );

  /// Whether [cycle] is new relative to the baseline.
  bool isNewCycle(Cycle cycle) => newCycles.contains(cycle);

  /// Whether [violation] is new relative to the baseline.
  bool isNewViolation(LayerViolation violation) =>
      newViolations.contains(violation);
}
