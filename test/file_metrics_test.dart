import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

FileNode _f(String p) => FileNode(relativePath: p, absolutePath: '/$p');

void main() {
  test('counts distinct import/export targets, not parts', () {
    final result = ScanResult(
      packageName: 'app',
      files: {
        for (final p in ['a', 'b', 'c', 'a_part']) p: _f(p),
      },
      edges: const [
        GraphEdge(from: 'a', to: 'b'),
        GraphEdge(from: 'a', to: 'b', type: 'export'),
        GraphEdge(from: 'a', to: 'c'),
        GraphEdge(from: 'a', to: 'a_part', type: 'part'),
        GraphEdge(from: 'c', to: 'b'),
      ],
    );
    final m = {for (final x in FileMetrics.compute(result)) x.file: x};
    expect(m['a']!.fanOut, 2);
    expect(m['a']!.fanIn, 0);
    expect(m['b']!.fanIn, 2);
    expect(m['a_part']!.fanIn, 0);
    expect(m['a']!.instability, 1.0);
    expect(m['c']!.instability, 0.5);
    // coupling 2, 2, 2, 0 → ties by path
    expect(FileMetrics.compute(result).map((x) => x.file).toList(), [
      'a',
      'b',
      'c',
      'a_part',
    ]);
  });
}
