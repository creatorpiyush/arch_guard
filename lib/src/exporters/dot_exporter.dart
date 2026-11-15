import '../graph/grouped_graph.dart';
import '../models/cycle.dart';
import '../models/scan_result.dart';

/// Exports the dependency graph and cycle analysis into Graphviz DOT syntax.
class DotExporter {
  /// Generates the DOT format content string.
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    String scope = 'cycles',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('digraph "Dependency Graph" {');
    buffer.writeln('  rankdir=LR;');
    buffer.writeln('  node [shape=box, style=filled, fontname="Helvetica"];');
    buffer.writeln('  edge [fontname="Helvetica"];');
    buffer.writeln();

    final cycleNodes = <String>{};
    for (final cycle in cycles) {
      cycleNodes.addAll(cycle.files);
    }

    final Set<String> targetNodes;
    if (scope == 'cycles') {
      targetNodes = cycleNodes.isEmpty
          ? result.files.keys.take(20).toSet()
          : cycleNodes;
    } else {
      targetNodes = result.files.keys.toSet();
    }

    // Cluster subgraphs for each cycle
    for (var i = 0; i < cycles.length; i++) {
      final cycle = cycles[i];
      buffer.writeln('  subgraph cluster_${i + 1} {');
      buffer.writeln('    label="Strongly Connected Component #${i + 1}";');
      buffer.writeln('    color="#ef4444";');
      buffer.writeln('    style=dashed;');
      buffer.writeln('    fontcolor="#ef4444";');
      for (final file in cycle.files) {
        buffer.writeln('    "${_escape(file)}";');
      }
      buffer.writeln('  }');
      buffer.writeln();
    }

    // Node declarations
    for (final nodePath in result.files.keys) {
      if (!targetNodes.contains(nodePath)) continue;
      final isCycle = cycleNodes.contains(nodePath);
      final fill = isCycle ? '#fee2e2' : '#f3f4f6';
      final color = isCycle ? '#b91c1c' : '#9ca3af';
      final fontColor = isCycle ? '#991b1b' : '#1f2937';
      final penWidth = isCycle ? '2.0' : '1.0';

      buffer.writeln(
        '  "${_escape(nodePath)}" [fillcolor="$fill", color="$color", fontcolor="$fontColor", penwidth=$penWidth];',
      );
    }
    buffer.writeln();

    // Edges
    for (final edge in result.edges) {
      if (!targetNodes.contains(edge.from) || !targetNodes.contains(edge.to)) {
        continue;
      }
      final isCycleEdge =
          cycleNodes.contains(edge.from) && cycleNodes.contains(edge.to);
      final color = isCycleEdge ? '#ef4444' : '#d1d5db';
      final penWidth = isCycleEdge ? '2.0' : '1.0';
      final style = switch (edge.type) {
        'export' => 'dashed',
        'part' => 'dotted',
        _ => 'solid',
      };

      buffer.writeln(
        '  "${_escape(edge.from)}" -> "${_escape(edge.to)}" [color="$color", penwidth=$penWidth, style=$style];',
      );
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generates DOT for [graph]: one node per group with its file count,
  /// edges labelled with the number of imports, and edges that break a rule
  /// in red.
  static String exportGrouped(GroupedGraph graph) {
    final buffer = StringBuffer()
      ..writeln('digraph "Dependency Graph" {')
      ..writeln('  rankdir=LR;')
      ..writeln(
        '  node [shape=box, style="filled,rounded", fontname="Helvetica", '
        'fillcolor="#f3f4f6", color="#9ca3af"];',
      )
      ..writeln('  edge [fontname="Helvetica", color="#6b7280"];')
      ..writeln();
    for (final MapEntry(:key, :value) in graph.groups.entries) {
      final files = '${value.length} file${value.length == 1 ? '' : 's'}';
      buffer.writeln('  "${_escape(key)}" [label="${_escape(key)}\\n$files"];');
    }
    buffer.writeln();
    for (final e in graph.edges) {
      final attrs = e.violations == 0
          ? 'label="${e.count}"'
          : 'label="${e.count}, ${e.violations} violation'
                '${e.violations == 1 ? '' : 's'}", color="#ef4444", '
                'fontcolor="#ef4444", penwidth=2.0';
      buffer.writeln('  "${_escape(e.from)}" -> "${_escape(e.to)}" [$attrs];');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  static String _escape(String str) {
    return str.replaceAll('"', '\\"');
  }
}
