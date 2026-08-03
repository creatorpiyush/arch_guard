import 'package:dep_graph_visualizer/dep_graph_visualizer.dart';
import 'package:test/test.dart';

void main() {
  group('SccComponent Metrics', () {
    test('computes architectural severity metrics and hub correctly', () {
      final outgoing = <String, Set<String>>{
        'a.dart': {'b.dart', 'c.dart'},
        'b.dart': {'a.dart'},
        'c.dart': {'a.dart'},
      };
      final incoming = <String, Set<String>>{
        'a.dart': {'b.dart', 'c.dart'},
        'b.dart': {'a.dart'},
        'c.dart': {'a.dart'},
      };

      final scc = SccComponent.compute(
        id: 1,
        files: ['a.dart', 'b.dart', 'c.dart'],
        exampleChain: ['a.dart', 'b.dart', 'a.dart'],
        outgoingEdges: outgoing,
        incomingEdges: incoming,
      );

      expect(scc.id, equals(1));
      expect(scc.files, containsAll(['a.dart', 'b.dart', 'c.dart']));
      expect(scc.internalEdgesCount, equals(4)); // a->b, a->c, b->a, c->a
      expect(scc.hubFile, equals('a.dart')); // a has degree 4 (2 out + 2 in)
      expect(scc.extraMembers, equals(['c.dart']));
      expect(scc.instability, greaterThanOrEqualTo(0.0));
      expect(scc.density, greaterThan(0.0));
    });
  });
}
