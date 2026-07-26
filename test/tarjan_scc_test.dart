import 'package:dep_graph_visualizer/src/graph/tarjan_scc.dart';
import 'package:test/test.dart';

void main() {
  group('TarjanScc', () {
    test('detects simple 2-node cycle', () {
      final nodes = {'a', 'b'};
      final adj = {
        'a': {'b'},
        'b': {'a'},
      };

      final sccs = TarjanScc.findSCCs(nodes: nodes, adjacencyList: adj);
      final multiNodeSccs = sccs.where((s) => s.length > 1).toList();

      expect(multiNodeSccs.length, equals(1));
      expect(multiNodeSccs.first.toSet(), equals({'a', 'b'}));
    });

    test('returns singletons for acyclic DAG', () {
      final nodes = {'a', 'b', 'c'};
      final adj = {
        'a': {'b'},
        'b': {'c'},
        'c': <String>{},
      };

      final sccs = TarjanScc.findSCCs(nodes: nodes, adjacencyList: adj);
      final multiNodeSccs = sccs.where((s) => s.length > 1).toList();

      expect(multiNodeSccs, isEmpty);
      expect(sccs.length, equals(3));
    });

    test('handles complex multi-cycle graph', () {
      final nodes = {'a', 'b', 'c', 'd', 'e'};
      final adj = {
        'a': {'b'},
        'b': {'c'},
        'c': {'a', 'd'}, // Cycle: a -> b -> c -> a
        'd': {'e'},
        'e': {'d'}, // Cycle: d -> e -> d
      };

      final sccs = TarjanScc.findSCCs(nodes: nodes, adjacencyList: adj);
      final multiNodeSccs = sccs.where((s) => s.length > 1).toList();

      expect(multiNodeSccs.length, equals(2));
    });
  });
}
