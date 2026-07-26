/// Helper to extract ordered example cyclic paths within SCC components.
class CyclePathFinder {
  /// Given an SCC set of node IDs [sccNodes] and [adjacencyList], finds a minimal cyclic chain `[a, b, c, ..., a]`.
  static List<String> findExampleChain({
    required List<String> sccNodes,
    required Map<String, Set<String>> adjacencyList,
  }) {
    if (sccNodes.isEmpty) return const [];

    final sccSet = sccNodes.toSet();

    // Check for self-loop
    for (final node in sccNodes) {
      final targets = adjacencyList[node] ?? const {};
      if (targets.contains(node)) {
        return [node, node];
      }
    }

    if (sccNodes.length == 1) {
      return sccNodes;
    }

    // Standard DFS to find a cycle within `sccSet`
    final startNode = sccNodes.first;
    final path = <String>[startNode];
    final visitedInPath = <String, int>{startNode: 0};

    List<String>? resultPath;

    bool dfs(String current) {
      final neighbors = adjacencyList[current] ?? const {};
      for (final next in neighbors) {
        if (!sccSet.contains(next)) continue;

        if (visitedInPath.containsKey(next)) {
          // Found cycle!
          final cycleStartIndex = visitedInPath[next]!;
          resultPath = [...path.sublist(cycleStartIndex), next];
          return true;
        } else {
          visitedInPath[next] = path.length;
          path.add(next);
          if (dfs(next)) return true;
          path.removeLast();
          visitedInPath.remove(next);
        }
      }
      return false;
    }

    dfs(startNode);

    if (resultPath != null) {
      return resultPath!;
    }

    // Fallback if DFS from first node didn't hit a closed loop (try other nodes)
    for (final node in sccNodes) {
      if (node == startNode) continue;
      path.clear();
      visitedInPath.clear();
      path.add(node);
      visitedInPath[node] = 0;
      if (dfs(node)) return resultPath!;
    }

    return sccNodes;
  }
}
