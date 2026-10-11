import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

List<GraphEdge> _edges(String spec) => [
  for (final pair in spec.split(' '))
    GraphEdge(from: pair.split('>')[0], to: pair.split('>')[1]),
];

void main() {
  group('CycleBreaker', () {
    test(
      'two files: removing either import breaks it; first in order wins',
      () {
        final hint = CycleBreaker.suggest(
          files: ['a', 'b'],
          edges: _edges('a>b b>a'),
        )!;
        expect('${hint.from}>${hint.to}', 'a>b');
        expect(hint.breaksCycle, isTrue);
        expect(hint.groupSize, 2);
      },
    );

    test('picks the edge shared by every loop', () {
      // Loops a>b>c>a and a>c>a both use c>a.
      final hint = CycleBreaker.suggest(
        files: ['a', 'b', 'c'],
        edges: _edges('a>b a>c b>c c>a'),
      )!;
      expect('${hint.from}>${hint.to}', 'c>a');
      expect(hint.breaksCycle, isTrue);
    });

    test('reports how far it shrinks when no single import breaks it', () {
      // a<->b and b<->c: any one removal leaves a 2-file cycle.
      final hint = CycleBreaker.suggest(
        files: ['a', 'b', 'c'],
        edges: _edges('a>b b>a b>c c>b'),
      )!;
      expect(hint.breaksCycle, isFalse);
      expect(hint.remainingLargestCycle, 2);
      expect(hint.describe(), contains('shrinks the group from 3 to 2 files'));
    });

    test('self-import', () {
      final hint = CycleBreaker.suggest(files: ['a'], edges: _edges('a>a'))!;
      expect(hint.breaksCycle, isTrue);
    });

    test('never suggests a part edge', () {
      final hint = CycleBreaker.suggest(
        files: ['a', 'b'],
        edges: const [
          GraphEdge(from: 'a', to: 'b', type: 'part'),
          GraphEdge(from: 'b', to: 'a', line: 4),
        ],
      )!;
      expect('${hint.from}>${hint.to}', 'b>a');
      expect(hint.line, 4);
      expect(hint.describe(), 'b:4 -> a (breaks the cycle)');

      expect(
        CycleBreaker.suggest(
          files: ['a', 'b'],
          edges: const [
            GraphEdge(from: 'a', to: 'b', type: 'part'),
            GraphEdge(from: 'b', to: 'a', type: 'part'),
          ],
        ),
        isNull,
      );
    });

    test('gives up above maxEdges', () {
      expect(
        CycleBreaker.suggest(
          files: ['a', 'b'],
          edges: _edges('a>b b>a'),
          maxEdges: 1,
        ),
        isNull,
      );
    });

    test('DependencyGraph attaches the hint to each cycle', () {
      const result = ScanResult(
        packageName: 'app',
        files: {
          'a': FileNode(relativePath: 'a', absolutePath: '/a'),
          'b': FileNode(relativePath: 'b', absolutePath: '/b'),
        },
        edges: [
          GraphEdge(from: 'a', to: 'b', line: 1),
          GraphEdge(from: 'b', to: 'a', line: 2),
        ],
      );
      final cycle = DependencyGraph.fromScanResult(
        result,
      ).findCircularDependencies().single;
      expect(
        cycle.scc!.suggestedBreak!.describe(),
        'a:1 -> b (breaks the cycle)',
      );
      expect(cycle.toJson()['scc']['suggestedBreak']['from'], 'a');
    });
  });
}
