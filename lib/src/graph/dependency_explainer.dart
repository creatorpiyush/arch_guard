import '../models/cycle.dart';
import 'dependency_graph.dart';

/// Explains dependency paths and SCC membership for individual target files.
class DependencyExplainer {
  /// Explains a target file within the given dependency graph and detected cycles.
  static String explainFile({
    required String targetFile,
    required DependencyGraph graph,
    required List<Cycle> cycles,
    bool color = true,
  }) {
    final buffer = StringBuffer();
    final normalizedTarget = targetFile.replaceAll('\\', '/');

    final matchedPath = graph.scanResult.nodePaths.firstWhere(
      (path) => path == normalizedTarget || path.endsWith(normalizedTarget),
      orElse: () => '',
    );

    if (matchedPath.isEmpty) {
      return 'File not found in scan graph: $targetFile';
    }

    final cRed = color ? '\x1B[31m' : '';
    final cGreen = color ? '\x1B[32m' : '';
    final cCyan = color ? '\x1B[36m' : '';
    final cBold = color ? '\x1B[1m' : '';
    final cReset = color ? '\x1B[0m' : '';

    buffer.writeln(
      '${cBold}Dependency Explanation for:$cReset $cCyan$matchedPath$cReset\n',
    );

    // Find SCC membership
    Cycle? targetCycle;
    for (final cycle in cycles) {
      if (cycle.files.contains(matchedPath)) {
        targetCycle = cycle;
        break;
      }
    }

    if (targetCycle != null) {
      final scc = targetCycle.scc;
      buffer.writeln(
        '${cBold}SCC Membership:$cReset ${cRed}Strongly Connected Component #${scc?.id ?? "1"}$cReset (${targetCycle.files.length} files)',
      );
      if (scc != null) {
        buffer.writeln('  • Internal Edges: ${scc.internalEdgesCount}');
        buffer.writeln(
          '  • Avg Fan-In: ${scc.averageFanIn} | Avg Fan-Out: ${scc.averageFanOut}',
        );
        buffer.writeln('  • Instability Metric: ${scc.instability}');
        buffer.writeln('  • Dependency Hub File: ${scc.hubFile}');
      }
      buffer.writeln('\n  ${cBold}Representative Cycle Chain:$cReset');
      buffer.writeln('  ${targetCycle.exampleChain.join(" -> ")}\n');
    } else {
      buffer.writeln(
        '${cBold}SCC Membership:$cReset ${cGreen}No circular dependencies (Not in any SCC)$cReset\n',
      );
    }

    // Incoming Edges
    final incoming = graph.incomingEdges[matchedPath] ?? {};
    buffer.writeln(
      '${cBold}Incoming Dependencies (${incoming.length}):$cReset',
    );
    if (incoming.isEmpty) {
      buffer.writeln('  (None)');
    } else {
      for (final inc in incoming) {
        buffer.writeln('  ← $inc');
      }
    }
    buffer.writeln();

    // Outgoing Edges
    final outgoing = graph.outgoingEdges[matchedPath] ?? {};
    buffer.writeln(
      '${cBold}Outgoing Dependencies (${outgoing.length}):$cReset',
    );
    if (outgoing.isEmpty) {
      buffer.writeln('  (None)');
    } else {
      for (final out in outgoing) {
        buffer.writeln('  → $out');
      }
    }

    return buffer.toString();
  }
}
