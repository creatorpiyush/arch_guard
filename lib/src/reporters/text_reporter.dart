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

    buffer.writeln('==================================================');
    buffer.writeln('$bold  Dependency Graph Visualizer - Scan Summary$reset');
    buffer.writeln('==================================================');
    buffer.writeln('Package Name:  $cyan${result.packageName}$reset');
    if (result.isWorkspace) {
      buffer.writeln('Workspace Pkgs:${result.workspacePackageCount}');
    }
    buffer.writeln('Files Scanned: ${result.files.length}');
    buffer.writeln('Graph Edges:   ${result.edges.length}');
    buffer.writeln(
      'Cycles Found:  ${cycles.isEmpty ? "${green}0$reset" : "$red${cycles.length}$reset"}',
    );
    buffer.writeln('==================================================');
    buffer.writeln();

    if (cycles.isEmpty) {
      buffer.writeln('$green✓ No circular dependencies found!$reset');
      return buffer.toString();
    }

    buffer.writeln('$red$bold[!] CIRCULAR DEPENDENCIES DETECTED:$reset');
    buffer.writeln();

    for (var i = 0; i < cycles.length; i++) {
      final cycle = cycles[i];
      final number = i + 1;
      buffer.writeln(
        '  ${bold}Cycle #$number (${cycle.files.length} files):$reset',
      );

      final chain = cycle.exampleChain;
      if (chain.isNotEmpty) {
        buffer.writeln('    $red${chain.first}$reset');
        for (var j = 1; j < chain.length; j++) {
          buffer.writeln('    $red-> ${chain[j]}$reset');
        }
      }

      final extra = cycle.extraMembers;
      if (extra.isNotEmpty) {
        buffer.writeln('    $dim(Also in group: ${extra.join(", ")})$reset');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}
