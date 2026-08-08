import '../models/cycle.dart';
import '../models/scan_result.dart';

/// Formats and prints scan results and detected cycles to text (terminal).
class TextReporter {
  final bool useColor;

  const TextReporter({this.useColor = true});

  /// Formats the complete report into a single string.
  String formatReport({
    required ScanResult result,
    required List<Cycle> cycles,
  }) {
    final buffer = StringBuffer();

    final reset = useColor ? '\x1B[0m' : '';
    final bold = useColor ? '\x1B[1m' : '';
    final red = useColor ? '\x1B[31m' : '';
    final green = useColor ? '\x1B[32m' : '';
    final cyan = useColor ? '\x1B[36m' : '';
    final dim = useColor ? '\x1B[2m' : '';

    final largestScc = cycles.isEmpty
        ? 0
        : cycles.fold<int>(
            0,
            (max, c) => c.files.length > max ? c.files.length : max,
          );
    final avgSccSize = cycles.isEmpty
        ? 0.0
        : cycles.fold<int>(0, (sum, c) => sum + c.files.length) / cycles.length;

    buffer.writeln('==================================================');
    buffer.writeln('$bold  arch_guard - Scan Summary$reset');
    buffer.writeln('==================================================');
    buffer.writeln('Package Name:  $cyan${result.packageName}$reset');
    if (result.isWorkspace) {
      buffer.writeln('Workspace Pkgs:${result.workspacePackageCount}');
    }
    buffer.writeln('Files Scanned: ${result.files.length}');
    buffer.writeln('Graph Edges:   ${result.edges.length}');
    buffer.writeln(
      'SCC Cycles:    ${cycles.isEmpty ? "${green}0$reset" : "$red${cycles.length}$reset"}',
    );
    if (cycles.isNotEmpty) {
      buffer.writeln('Largest SCC:   $largestScc files');
      buffer.writeln('Average SCC:   ${avgSccSize.toStringAsFixed(1)} files');
    }
    buffer.writeln('==================================================');
    buffer.writeln();

    if (cycles.isEmpty) {
      buffer.writeln('$green✓ No circular dependencies found!$reset');
      return buffer.toString();
    }

    buffer.writeln(
      '$red$bold[!] STRONGLY CONNECTED COMPONENTS (SCCs) DETECTED:$reset',
    );
    buffer.writeln();

    for (var i = 0; i < cycles.length; i++) {
      final cycle = cycles[i];
      final number = i + 1;
      final scc = cycle.scc;

      buffer.writeln(
        '  ${bold}Strongly Connected Component #$number (${cycle.files.length} files)$reset',
      );

      if (scc != null) {
        buffer.writeln(
          '    $dim[Metrics: ${scc.internalEdgesCount} internal edges | Avg Fan-In: ${scc.averageFanIn} | Avg Fan-Out: ${scc.averageFanOut} | Hub: ${scc.hubFile}]$reset',
        );
      }

      final chain = cycle.exampleChain;
      if (chain.isNotEmpty) {
        buffer.writeln('    ${bold}Representative Cycle Path:$reset');
        buffer.writeln('    $red${chain.first}$reset');
        for (var j = 1; j < chain.length; j++) {
          buffer.writeln('    $red-> ${chain[j]}$reset');
        }
      }

      final extra = cycle.extraMembers;
      if (extra.isNotEmpty) {
        buffer.writeln('    $dim• Additional Files: ${extra.join(", ")}$reset');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}
