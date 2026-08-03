import 'dart:convert';
import '../models/cycle.dart';
import '../models/scan_result.dart';

/// Exports scan results and detected circular dependency SCCs to machine-readable JSON format.
class JsonExporter {
  /// Serializes scan details, nodes, edges, and detected SCC cycles to a formatted JSON string.
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    List<Map<String, dynamic>>? layerViolations,
  }) {
    final payload = {
      'packageName': result.packageName,
      'isWorkspace': result.isWorkspace,
      'workspacePackageCount': result.workspacePackageCount,
      'summary': {
        'totalFiles': result.files.length,
        'totalEdges': result.edges.length,
        'sccCount': cycles.length,
        'largestSccSize': cycles.fold<int>(
          0,
          (max, c) => c.files.length > max ? c.files.length : max,
        ),
      },
      'cycles': cycles.map((c) => c.toJson()).toList(),
      'nodes': result.files.values.map((f) => f.toJson()).toList(),
      'edges': result.edges
          .map((e) => {'from': e.from, 'to': e.to, 'type': e.type})
          .toList(),
      'layerViolations': ?layerViolations,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
