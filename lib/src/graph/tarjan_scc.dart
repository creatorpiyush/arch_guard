import 'dart:math';

/// Iterative implementation of Tarjan's Strongly Connected Components (SCC) algorithm.
class TarjanScc {
  /// Finds all strongly connected components in a directed graph.
  ///
  /// [nodes] is the set of all node IDs.
  /// [adjacencyList] maps each node to its outgoing target nodes.
  static List<List<String>> findSCCs({
    required Set<String> nodes,
    required Map<String, Set<String>> adjacencyList,
  }) {
    int index = 0;
    final nodeIndex = <String, int>{};
    final nodeLowLink = <String, int>{};
    final onStack = <String, bool>{};
    final stack = <String>[];
    final sccs = <List<String>>[];

    // Auxiliary frame for non-recursive traversal
    for (final node in nodes) {
      if (nodeIndex.containsKey(node)) continue;

      // Start iterative DFS from `node`
      final dfsStack = <_DFSFrame>[
        _DFSFrame(node, adjacencyList[node]?.toList() ?? []),
      ];

      nodeIndex[node] = index;
      nodeLowLink[node] = index;
      index++;
      stack.add(node);
      onStack[node] = true;

      while (dfsStack.isNotEmpty) {
        final currentFrame = dfsStack.last;
        final u = currentFrame.node;

        if (currentFrame.neighborIndex < currentFrame.neighbors.length) {
          final v = currentFrame.neighbors[currentFrame.neighborIndex];
          currentFrame.neighborIndex++;

          if (!nodeIndex.containsKey(v)) {
            // Unvisited neighbor
            nodeIndex[v] = index;
            nodeLowLink[v] = index;
            index++;
            stack.add(v);
            onStack[v] = true;

            dfsStack.add(_DFSFrame(v, adjacencyList[v]?.toList() ?? []));
          } else if (onStack[v] == true) {
            // Neighbor is on stack (back-edge)
            nodeLowLink[u] = min(nodeLowLink[u]!, nodeIndex[v]!);
          }
        } else {
          // Finished exploring all neighbors of `u`
          dfsStack.removeLast();

          if (dfsStack.isNotEmpty) {
            final parent = dfsStack.last.node;
            nodeLowLink[parent] = min(nodeLowLink[parent]!, nodeLowLink[u]!);
          }

          // If `u` is a root node of an SCC
          if (nodeLowLink[u] == nodeIndex[u]) {
            final component = <String>[];
            while (true) {
              final w = stack.removeLast();
              onStack[w] = false;
              component.add(w);
              if (w == u) break;
            }
            sccs.add(component);
          }
        }
      }
    }

    return sccs;
  }
}

class _DFSFrame {
  final String node;
  final List<String> neighbors;
  int neighborIndex = 0;

  _DFSFrame(this.node, this.neighbors);
}
