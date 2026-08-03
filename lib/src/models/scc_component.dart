/// Represents a Strongly Connected Component (SCC) in the dependency graph
/// with architectural severity metrics.
class SccComponent {
  /// Unique identifier or index of the component (1-based).
  final int id;

  /// Files participating in this component.
  final List<String> files;

  /// Representative cycle path chain (e.g. `['a.dart', 'b.dart', 'a.dart']`).
  final List<String> exampleChain;

  /// Total internal dependency edges between files in this SCC.
  final int internalEdgesCount;

  /// Average Fan-In (incoming dependencies per node within SCC).
  final double averageFanIn;

  /// Average Fan-Out (outgoing dependencies per node within SCC).
  final double averageFanOut;

  /// Instability metric: `FanOut / (FanIn + FanOut)` ranging from 0.0 (stable) to 1.0 (unstable).
  final double instability;

  /// Architectural density metric: `internalEdges / (N * (N - 1))` for N > 1.
  final double density;

  /// File path acting as the main dependency hub in this component.
  final String hubFile;

  const SccComponent({
    required this.id,
    required this.files,
    required this.exampleChain,
    required this.internalEdgesCount,
    required this.averageFanIn,
    required this.averageFanOut,
    required this.instability,
    required this.density,
    required this.hubFile,
  });

  /// Additional files in this component not on the main representative chain.
  List<String> get extraMembers {
    final chainSet = exampleChain.toSet();
    return files.where((f) => !chainSet.contains(f)).toList();
  }

  /// Calculates SCC metrics from a list of files, example chain, and graph edge lookup.
  factory SccComponent.compute({
    required int id,
    required List<String> files,
    required List<String> exampleChain,
    required Map<String, Set<String>> outgoingEdges,
    required Map<String, Set<String>> incomingEdges,
  }) {
    final fileSet = files.toSet();
    int internalEdges = 0;
    int totalFanIn = 0;
    int totalFanOut = 0;
    String topHub = files.isNotEmpty ? files.first : '';
    int maxDegree = -1;

    for (final file in files) {
      final out = outgoingEdges[file] ?? const {};
      final inc = incomingEdges[file] ?? const {};

      final internalOut = out
          .where((target) => fileSet.contains(target))
          .length;
      internalEdges += internalOut;
      totalFanOut += out.length;
      totalFanIn += inc.length;

      final degree = out.length + inc.length;
      if (degree > maxDegree) {
        maxDegree = degree;
        topHub = file;
      }
    }

    final n = files.length;
    final avgIn = n > 0 ? totalFanIn / n : 0.0;
    final avgOut = n > 0 ? totalFanOut / n : 0.0;
    final instab = (totalFanIn + totalFanOut) > 0
        ? totalFanOut / (totalFanIn + totalFanOut)
        : 0.0;
    final dens = (n > 1) ? internalEdges / (n * (n - 1)) : 1.0;

    return SccComponent(
      id: id,
      files: files,
      exampleChain: exampleChain,
      internalEdgesCount: internalEdges,
      averageFanIn: double.parse(avgIn.toStringAsFixed(2)),
      averageFanOut: double.parse(avgOut.toStringAsFixed(2)),
      instability: double.parse(instab.toStringAsFixed(2)),
      density: double.parse(dens.toStringAsFixed(2)),
      hubFile: topHub,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'files': files,
    'exampleChain': exampleChain,
    'internalEdgesCount': internalEdgesCount,
    'averageFanIn': averageFanIn,
    'averageFanOut': averageFanOut,
    'instability': instability,
    'density': density,
    'hubFile': hubFile,
  };
}
