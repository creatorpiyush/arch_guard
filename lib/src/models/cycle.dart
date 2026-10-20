import 'scc_component.dart';

/// Describes a detected circular dependency group (Strongly Connected Component).
class Cycle {
  /// All files involved in this strongly connected component (SCC).
  final List<String> files;

  /// Ordered chain representing a concrete circular path, e.g., `['a.dart', 'b.dart', 'a.dart']`.
  final List<String> exampleChain;

  /// Optional underlying architectural SCC metrics.
  final SccComponent? scc;

  /// Conditions of the conditional imports this cycle depends on, sorted
  /// (`dart.library.io`, `default`). Empty when the plain imports alone
  /// form a cycle, so it exists on every platform.
  final List<String> platformConditions;

  /// Creates a cycle over [files], illustrated by [exampleChain].
  const Cycle({
    required this.files,
    required this.exampleChain,
    this.scc,
    this.platformConditions = const [],
  });

  /// Whether the cycle only exists through conditional imports, so only on
  /// some platforms.
  bool get isPlatformSpecific => platformConditions.isNotEmpty;

  /// ` (only through conditional imports: if (dart.library.io))`, or empty.
  String get platformNote => isPlatformSpecific
      ? ' (only through conditional imports: '
            '${platformConditions.map((c) => c == 'default' ? c : 'if ($c)').join(', ')})'
      : '';

  /// Additional files in this strongly connected component that are not on the main example chain.
  List<String> get extraMembers {
    final chainSet = exampleChain.toSet();
    return files.where((f) => !chainSet.contains(f)).toList();
  }

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'files': files,
    'exampleChain': exampleChain,
    if (scc != null) 'scc': scc!.toJson(),
    if (platformConditions.isNotEmpty) 'platformConditions': platformConditions,
  };

  @override
  String toString() =>
      'Cycle(chain: ${exampleChain.join(" -> ")}, members: ${files.length})';
}
