import 'dart:typed_data';

import '../models/scan_result.dart';

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

    // Int-indexed graph built once; each candidate only skips its pair.
    final n = files.length;
    final index = {for (var i = 0; i < n; i++) files[i]: i};
    final adjacency = [for (var i = 0; i < n; i++) <int>[]];
    final pairs = <int>{};
    // A pair also linked by a `part` directive stays linked after the cut.
    final partPairs = <int>{};
    for (final e in internal) {
      final a = index[e.from]!, b = index[e.to]!;
      if (pairs.add(a * n + b)) adjacency[a].add(b);
      if (e.type == 'part') partPairs.add(a * n + b);
    }

    CycleBreak? best;
    for (final cut in candidates) {
      final code = index[cut.from]! * n + index[cut.to]!;
      final remaining = _largestCycle(
        adjacency,
        partPairs.contains(code) ? -1 : code,
      );
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

  /// Size of the largest cycle in [adjacency] (a self-import counts as 1)
  /// with the edge `skip ~/ n -> skip % n` left out; iterative Tarjan.
  static int _largestCycle(List<List<int>> adjacency, int skip) {
    final n = adjacency.length;
    final order = Int32List(n)..fillRange(0, n, -1);
    final low = Int32List(n);
    final onStack = List<bool>.filled(n, false);
    final stack = <int>[];
    final callNode = Int32List(n);
    final callEdge = Int32List(n);
    var counter = 0;
    var largest = 0;
    for (var root = 0; root < n; root++) {
      if (order[root] != -1) continue;
      var depth = 0;
      callNode[0] = root;
      callEdge[0] = 0;
      order[root] = low[root] = counter++;
      stack.add(root);
      onStack[root] = true;
      while (depth >= 0) {
        final u = callNode[depth];
        final out = adjacency[u];
        if (callEdge[depth] < out.length) {
          final v = out[callEdge[depth]++];
          if (u * n + v == skip) continue;
          if (order[v] == -1) {
            order[v] = low[v] = counter++;
            stack.add(v);
            onStack[v] = true;
            depth++;
            callNode[depth] = v;
            callEdge[depth] = 0;
          } else if (onStack[v] && order[v] < low[u]) {
            low[u] = order[v];
          }
          continue;
        }
        depth--;
        if (depth >= 0) {
          final parent = callNode[depth];
          if (low[u] < low[parent]) low[parent] = low[u];
        }
        if (low[u] == order[u]) {
          var size = 0;
          int w;
          do {
            w = stack.removeLast();
            onStack[w] = false;
            size++;
          } while (w != u);
          // A lone file is a cycle only if it imports itself.
          if (size == 1 && (u * n + u == skip || !adjacency[u].contains(u))) {
            size = 0;
          }
          if (size > largest) largest = size;
        }
      }
    }
    return largest;
  }
}
