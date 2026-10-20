import '../models/cycle.dart';
import '../models/scan_result.dart';
import 'cycle_breaker.dart';
import 'cycle_path_finder.dart';
import 'tarjan_scc.dart';

import '../models/scc_component.dart';

/// Represents the dependency graph of a scanned Dart project.
class DependencyGraph {
  /// The underlying scan result metadata.
  final ScanResult scanResult;

  /// Map from file path to set of file paths it imports/exports (outgoing edges).
  final Map<String, Set<String>> outgoingEdges;

  /// Map from file path to set of file paths that import/export it (incoming edges).
  final Map<String, Set<String>> incomingEdges;

  DependencyGraph._({
    required this.scanResult,
    required this.outgoingEdges,
    required this.incomingEdges,
  });

  /// Factory constructor to construct a graph from a [ScanResult].
  factory DependencyGraph.fromScanResult(ScanResult result) {
    final outgoing = <String, Set<String>>{};
    final incoming = <String, Set<String>>{};

    for (final nodePath in result.nodePaths) {
      outgoing[nodePath] = <String>{};
      incoming[nodePath] = <String>{};
    }

    for (final edge in result.edges) {
      outgoing.putIfAbsent(edge.from, () => <String>{}).add(edge.to);
      incoming.putIfAbsent(edge.to, () => <String>{}).add(edge.from);
      // Ensure destination node is represented in graph keys
      outgoing.putIfAbsent(edge.to, () => <String>{});
      incoming.putIfAbsent(edge.from, () => <String>{});
    }

    return DependencyGraph._(
      scanResult: result,
      outgoingEdges: outgoing,
      incomingEdges: incoming,
    );
  }

  /// Finds all circular dependencies in the graph.
  List<Cycle> findCircularDependencies() {
    final allNodes = outgoingEdges.keys.toSet();
    final sccs = TarjanScc.findSCCs(
      nodes: allNodes,
      adjacencyList: outgoingEdges,
    );

    final cycles = <Cycle>[];
    int sccIndex = 1;

    for (final scc in sccs) {
      if (scc.length > 1) {
        // Multi-node cycle
        final exampleChain = CyclePathFinder.findExampleChain(
          sccNodes: scc,
          adjacencyList: outgoingEdges,
        );
        final sccComp = SccComponent.compute(
          id: sccIndex++,
          files: scc,
          exampleChain: exampleChain,
          outgoingEdges: outgoingEdges,
          incomingEdges: incomingEdges,
          suggestedBreak: CycleBreaker.suggest(
            files: scc,
            edges: scanResult.edges,
          ),
        );
        cycles.add(
          Cycle(
            files: scc,
            exampleChain: exampleChain,
            scc: sccComp,
            platformConditions: _platformConditions(scc),
          ),
        );
      } else if (scc.length == 1) {
        final node = scc.first;
        final targets = outgoingEdges[node] ?? const {};
        if (targets.contains(node)) {
          // Self-import cycle
          final exampleChain = [node, node];
          final sccComp = SccComponent.compute(
            id: sccIndex++,
            files: scc,
            exampleChain: exampleChain,
            outgoingEdges: outgoingEdges,
            incomingEdges: incomingEdges,
            suggestedBreak: CycleBreaker.suggest(
              files: scc,
              edges: scanResult.edges,
            ),
          );
          cycles.add(
            Cycle(
              files: scc,
              exampleChain: exampleChain,
              scc: sccComp,
              platformConditions: _platformConditions(scc),
            ),
          );
        }
      }
    }

    return cycles;
  }

  /// Conditions of the conditional edges inside [scc] when its plain edges
  /// alone contain no cycle, otherwise empty (the cycle exists everywhere).
  List<String> _platformConditions(List<String> scc) {
    final members = scc.toSet();
    final plain = {for (final f in scc) f: <String>{}};
    final conditions = <String>{};
    for (final edge in scanResult.edges) {
      if (!members.contains(edge.from) || !members.contains(edge.to)) continue;
      final condition = edge.condition;
      if (condition == null) {
        plain[edge.from]!.add(edge.to);
      } else {
        conditions.add(condition);
      }
    }
    if (conditions.isEmpty) return const [];
    final plainCycle = TarjanScc.findSCCs(
      nodes: members,
      adjacencyList: plain,
    ).any((c) => c.length > 1 || plain[c.first]!.contains(c.first));
    return plainCycle ? const [] : (conditions.toList()..sort());
  }
}
