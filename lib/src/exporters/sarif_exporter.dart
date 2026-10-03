import 'dart:convert';

import '../baseline/baseline.dart';
import '../checker/layer_validator.dart';
import '../models/cycle.dart';
import '../models/scan_result.dart';
import '../version.dart';

/// Exports cycles and layer violations as SARIF 2.1.0, the format read by
/// GitHub Code Scanning, Azure DevOps and most IDE SARIF viewers.
class SarifExporter {
  static const _infoUri = 'https://github.com/creatorpiyush/arch_guard';

  /// SARIF rule id for layer violations.
  static const layerViolationRule = 'layer-violation';

  /// SARIF rule id for circular dependency groups.
  static const circularDependencyRule = 'circular-dependency';

  /// SARIF rule id for groups larger than `max_scc_size`.
  static const sccSizeLimitRule = 'scc-size-limit';

  /// Serializes the analysis to a SARIF log.
  ///
  /// [uriPrefix] is prepended to every file path, so paths can be made
  /// relative to the repository root when the scanned project is a
  /// subdirectory (e.g. `packages/app/`). When [baseline] is given, each
  /// result carries `baselineState` (`new` or `unchanged`).
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    List<LayerViolation> layerViolations = const [],
    BaselineComparison? baseline,
    List<Cycle> oversizedCycles = const [],
    int? maxSccSize,
    bool failOnCycle = true,
    bool failOnLayerViolation = true,
    String uriPrefix = '',
  }) {
    final lineOf = <String, int>{};
    for (final edge in result.edges) {
      if (edge.line != null) {
        lineOf.putIfAbsent('${edge.from}\n${edge.to}', () => edge.line!);
      }
    }

    Map<String, dynamic> location(String file, {int? line, String? message}) =>
        {
          'physicalLocation': {
            'artifactLocation': {
              'uri': '$uriPrefix$file',
              'uriBaseId': '%SRCROOT%',
            },
            'region': {'startLine': line ?? 1},
          },
          'message': ?(message == null ? null : {'text': message}),
        };

    String? state(bool isNew) =>
        baseline == null ? null : (isNew ? 'new' : 'unchanged');

    final results = <Map<String, dynamic>>[];

    for (final v in layerViolations) {
      results.add({
        'ruleId': layerViolationRule,
        'level': failOnLayerViolation ? 'error' : 'warning',
        'message': {
          'text':
              '`${v.sourceFile}` (layer `${v.sourceLayer}`) imports '
              '`${v.targetFile}` (layer `${v.targetLayer}`). ${v.rule} '
              '${v.suggestion}',
        },
        'locations': [location(v.sourceFile, line: v.line)],
        'partialFingerprints': {
          'archGuard/v1': '$layerViolationRule:${Baseline.violationKey(v)}',
        },
        'baselineState': ?state(baseline?.isNewViolation(v) ?? true),
      });
    }

    for (final cycle in cycles) {
      final chain = cycle.exampleChain.isNotEmpty
          ? cycle.exampleChain
          : cycle.files;
      final first = chain.first;
      final next = chain.length > 1 ? chain[1] : null;
      final related = <Map<String, dynamic>>[];
      for (var i = 1; i < chain.length - 1; i++) {
        related.add({
          'id': i,
          ...location(
            chain[i],
            line: lineOf['${chain[i]}\n${chain[i + 1]}'],
            message: 'imports ${chain[i + 1]}',
          ),
        });
      }
      final id = cycle.scc?.id;
      results.add({
        'ruleId': circularDependencyRule,
        'level': failOnCycle ? 'error' : 'warning',
        'message': {
          'text':
              'Circular dependency (${id != null ? 'SCC #$id, ' : ''}'
              '${cycle.files.length} files): ${chain.join(' → ')}',
        },
        'locations': [
          location(first, line: next == null ? null : lineOf['$first\n$next']),
        ],
        if (related.isNotEmpty) 'relatedLocations': related,
        'partialFingerprints': {
          'archGuard/v1':
              '$circularDependencyRule:${(cycle.files.toList()..sort()).join('|')}',
        },
        'baselineState': ?state(baseline?.isNewCycle(cycle) ?? true),
      });
    }

    for (final cycle in oversizedCycles) {
      final hub = cycle.scc?.hubFile ?? cycle.files.first;
      results.add({
        'ruleId': sccSizeLimitRule,
        'level': 'error',
        'message': {
          'text':
              'Circular dependency group has ${cycle.files.length} files, '
              'more than max_scc_size ($maxSccSize). Hub file: $hub',
        },
        'locations': [location(hub)],
        'partialFingerprints': {
          'archGuard/v1':
              '$sccSizeLimitRule:${(cycle.files.toList()..sort()).join('|')}',
        },
        'baselineState': ?state(baseline?.isNewCycle(cycle) ?? true),
      });
    }

    final log = {
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'arch_guard',
              'version': packageVersion,
              'semanticVersion': packageVersion,
              'informationUri': _infoUri,
              'rules': _rules,
            },
          },
          'results': results,
        },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(log);
  }

  static const _rules = [
    {
      'id': layerViolationRule,
      'name': 'LayerViolation',
      'shortDescription': {'text': 'Import crosses a forbidden layer boundary'},
      'fullDescription': {
        'text':
            'A file imports a file from a layer that its own layer is not '
            'allowed to depend on (see `allowed_imports` in arch_guard.yaml).',
      },
      'helpUri': '$_infoUri#configuration-arch_guardyaml-or-pubspecyaml',
      'defaultConfiguration': {'level': 'error'},
      'properties': {
        'tags': ['architecture', 'maintainability'],
      },
    },
    {
      'id': circularDependencyRule,
      'name': 'CircularDependency',
      'shortDescription': {'text': 'Files depend on each other in a cycle'},
      'fullDescription': {
        'text':
            'These files form a strongly connected component: each one '
            'depends, directly or indirectly, on all the others.',
      },
      'helpUri': _infoUri,
      'defaultConfiguration': {'level': 'error'},
      'properties': {
        'tags': ['architecture', 'maintainability'],
      },
    },
    {
      'id': sccSizeLimitRule,
      'name': 'SccSizeLimit',
      'shortDescription': {'text': 'Circular dependency group is too large'},
      'fullDescription': {
        'text':
            'A circular dependency group has more files than the '
            '`max_scc_size` configured in arch_guard.yaml.',
      },
      'helpUri': '$_infoUri#configuration-arch_guardyaml-or-pubspecyaml',
      'defaultConfiguration': {'level': 'error'},
      'properties': {
        'tags': ['architecture', 'maintainability'],
      },
    },
  ];
}
