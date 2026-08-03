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

    // Map file path to safe Mermaid node IDs
    String sanitizeId(String path) {
      return path.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    }

    // Write nodes
    for (final file in targetNodes) {
      final id = sanitizeId(file);
      final isCyclic = cyclicFiles.contains(file);
      if (isCyclic) {
        buffer.writeln('    $id["$file"]:::cyclicNode');
      } else {
        buffer.writeln('    $id["$file"]');
      }
    }

    // Write edges
    for (final edge in result.edges) {
      if (targetNodes.contains(edge.from) && targetNodes.contains(edge.to)) {
        final fromId = sanitizeId(edge.from);
        final toId = sanitizeId(edge.to);
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
