import '../models/scan_result.dart';
import 'tarjan_scc.dart';

/// One import whose removal breaks (or shrinks) a circular dependency group.
class CycleBreak {
  /// File containing the import.
  final String from;

  /// Imported file.
  final String to;

  /// 1-based line of the import in [from], if known.
  final int? line;

  /// Number of files in the group before the import is removed.
  final int groupSize;

  /// Files in the largest cycle left after removal; `0` when none is left.
  final int remainingLargestCycle;

  /// Creates a hint.
  const CycleBreak({
    required this.from,
    required this.to,
    required this.groupSize,
    required this.remainingLargestCycle,
    this.line,
  });

  /// Whether removing the import leaves no cycle among the group's files.
  bool get breaksCycle => remainingLargestCycle == 0;

  /// E.g. `lib/a.dart:3 -> lib/b.dart (breaks the cycle)`.
  String describe() =>
      '$from${line != null ? ':$line' : ''} -> $to '
      '(${breaksCycle ? 'breaks the cycle' : 'shrinks the group from $groupSize to $remainingLargestCycle files'})';

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'line': ?line,
    'breaksCycle': breaksCycle,
    'remainingLargestCycle': remainingLargestCycle,
  };
}

/// Suggests which import to remove to break a circular dependency group.
class CycleBreaker {
  /// Tries removing each import/export edge inside [files] and returns the
  /// one that leaves the smallest remaining cycle (ties: first in sorted
  /// order), or `null` if there is no candidate or more than [maxEdges].
  static CycleBreak? suggest({
    required List<String> files,
    required List<GraphEdge> edges,
    int maxEdges = 2000,
  }) {
    final fileSet = files.toSet();
    final internal = <GraphEdge>[
      for (final e in edges)
        if (fileSet.contains(e.from) && fileSet.contains(e.to)) e,
    ];
    // One candidate per file pair, pointing at its first import/export line.
    final byPair = <String, GraphEdge>{};
    for (final e in internal) {
      if (e.type == 'part') continue;
      final key = '${e.from}\n${e.to}';
      final seen = byPair[key];
      if (seen == null ||
          (e.line != null && (seen.line == null || e.line! < seen.line!))) {
        byPair[key] = e;
      }
    }
    final candidates = byPair.values.toList()
      ..sort((a, b) {
        final c = a.from.compareTo(b.from);
        return c != 0 ? c : a.to.compareTo(b.to);
      });
    // ponytail: E × (V+E) per group; past maxEdges we skip the hint rather
    // than slow the run. Upgrade path: a greedy feedback-arc-set heuristic.
    if (candidates.isEmpty || candidates.length > maxEdges) return null;

    CycleBreak? best;
    for (final cut in candidates) {
      final adjacency = {for (final f in files) f: <String>{}};
      for (final e in internal) {
        if (e.from == cut.from && e.to == cut.to && e.type != 'part') continue;
        adjacency[e.from]!.add(e.to);
      }
      final remaining = _largestCycle(fileSet, adjacency);
      if (best == null || remaining < best.remainingLargestCycle) {
        best = CycleBreak(
          from: cut.from,
          to: cut.to,
          line: cut.line,
          groupSize: files.length,
          remainingLargestCycle: remaining,
        );
        if (remaining == 0) break;
      }
    }
    return best;
  }

  static int _largestCycle(
    Set<String> nodes,
    Map<String, Set<String>> adjacency,
  ) {
    var largest = 0;
    for (final scc in TarjanScc.findSCCs(
      nodes: nodes,
      adjacencyList: adjacency,
    )) {
      final size = scc.length > 1
          ? scc.length
          : (adjacency[scc.first]!.contains(scc.first) ? 1 : 0);
      if (size > largest) largest = size;
    }
    return largest;
  }
}
