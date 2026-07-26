/// Describes a detected circular dependency group.
class Cycle {
  /// All files involved in this strongly connected component (SCC).
  final List<String> files;

  /// Ordered chain representing a concrete circular path, e.g., `['a.dart', 'b.dart', 'a.dart']`.
  final List<String> exampleChain;

  const Cycle({required this.files, required this.exampleChain});

  /// Additional files in this strongly connected component that are not on the main example chain.
  List<String> get extraMembers {
    final chainSet = exampleChain.toSet();
    return files.where((f) => !chainSet.contains(f)).toList();
  }

  @override
  String toString() =>
      'Cycle(chain: ${exampleChain.join(" -> ")}, members: ${files.length})';
}
