import '../models/cycle.dart';
import '../models/scan_result.dart';

/// Exports dependency graphs to Mermaid markdown flowchart format (`.mmd`),
/// suitable for native rendering in GitHub/GitLab PRs and markdown files.
class MermaidExporter {
  /// Generates a Mermaid markdown string.
  /// If [scope] is 'cycles', only nodes and edges involved in SCC cycles are included.
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    String scope = 'cycles',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('```mermaid');
    buffer.writeln('flowchart TD');

    final cyclicFiles = cycles.expand((c) => c.files).toSet();

    // Collect relevant nodes
    final Set<String> targetNodes;
    if (scope == 'cycles') {
      targetNodes = cyclicFiles;
    } else {
      targetNodes = result.files.keys.toSet();
    }

    if (targetNodes.isEmpty) {
      buffer.writeln('    %% No circular dependencies detected');
      buffer.writeln('```');
      return buffer.toString();
    }

    // Map each file path to a unique, safe Mermaid node ID. Different paths
    // can sanitize to the same base ID (e.g. "a-b.dart" and "a_b.dart" both
    // become "a_b_dart"), so collisions are disambiguated with a numeric
    // suffix rather than silently merging distinct files in the diagram.
    final idByPath = <String, String>{};
    final usedIds = <String>{};
    for (final file in targetNodes) {
      final base = file.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      var candidate = base;
      var suffix = 1;
      while (!usedIds.add(candidate)) {
        candidate = '${base}_${suffix++}';
      }
      idByPath[file] = candidate;
    }

    // Mermaid node labels: escape quotes so they can't break out of the
    // `["..."]` label syntax.
    String sanitizeLabel(String path) => path.replaceAll('"', '#quot;');

    // Write nodes
    for (final file in targetNodes) {
      final id = idByPath[file]!;
      final label = sanitizeLabel(file);
      final isCyclic = cyclicFiles.contains(file);
      if (isCyclic) {
        buffer.writeln('    $id["$label"]:::cyclicNode');
      } else {
        buffer.writeln('    $id["$label"]');
      }
    }

    // Write edges
    for (final edge in result.edges) {
      if (targetNodes.contains(edge.from) && targetNodes.contains(edge.to)) {
        final fromId = idByPath[edge.from]!;
        final toId = idByPath[edge.to]!;
        final arrow = edge.type == 'export' ? '-. export .->' : '-->';
        buffer.writeln('    $fromId $arrow $toId');
      }
    }

    // Apply styling for cyclic nodes
    if (cyclicFiles.isNotEmpty) {
      buffer.writeln(
        '    classDef cyclicNode fill:#ff4d4d,stroke:#b30000,stroke-width:2px,color:#fff;',
      );
    }

    buffer.writeln('```');
    return buffer.toString();
  }
}
