import '../baseline/baseline.dart';
import '../checker/layer_validator.dart';
import '../models/cycle.dart';
import '../models/scan_result.dart';
import 'mermaid_exporter.dart';

/// Exports a Markdown summary for pull request comments and CI job summaries.
///
/// Leads with what is new relative to the baseline, then embeds the Mermaid
/// graph of the cycles (GitHub and GitLab render it natively).
class MarkdownExporter {
  /// Hidden marker so CI can find and update its previous comment.
  static const marker = '<!-- arch_guard-report -->';

  /// Longest Mermaid block to embed; GitHub refuses to render much larger ones.
  static const maxMermaidLength = 40000;

  /// Most items listed per section, to stay under comment size limits.
  static const maxListedItems = 50;

  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    List<LayerViolation> layerViolations = const [],
    BaselineComparison? baseline,
    List<Cycle> oversizedCycles = const [],
    int? maxSccSize,
  }) {
    final comparison =
        baseline ??
        BaselineComparison.allNew(
          cycles: cycles,
          layerViolations: layerViolations,
        );
    final newCycles = comparison.newCycles;
    final newViolations = comparison.newViolations;
    final newOversized = oversizedCycles.where(comparison.isNewCycle).toList();
    final hasNew =
        newCycles.isNotEmpty ||
        newViolations.isNotEmpty ||
        newOversized.isNotEmpty;

    final b = StringBuffer()
      ..writeln(marker)
      ..writeln('## arch_guard report')
      ..writeln();

    if (hasNew) {
      b.writeln(
        baseline == null
            ? '❌ **Architecture problems found.**'
            : '❌ **New architecture problems found** (not in the baseline).',
      );
    } else if (cycles.isEmpty && layerViolations.isEmpty) {
      b.writeln('✅ **No circular dependencies or layer violations.**');
    } else {
      b.writeln(
        '✅ **No new architecture problems.** Known problems are '
        'listed in the baseline.',
      );
    }
    b.writeln();

    b
      ..writeln('| | Total | New |')
      ..writeln('| :--- | ---: | ---: |')
      ..writeln(
        '| Circular dependency groups | ${cycles.length} | ${newCycles.length} |',
      )
      ..writeln(
        '| Layer violations | ${layerViolations.length} | '
        '${newViolations.length} |',
      );
    if (maxSccSize != null) {
      b.writeln(
        '| Groups over `max_scc_size` ($maxSccSize) | '
        '${oversizedCycles.length} | ${newOversized.length} |',
      );
    }
    b
      ..writeln('| Files scanned | ${result.files.length} | |')
      ..writeln();

    if (newViolations.isNotEmpty) {
      b.writeln('### New layer violations');
      b.writeln();
      _writeCapped(b, newViolations, (v) {
        final at = v.line != null ? ':${v.line}' : '';
        return '- `${v.sourceFile}$at` (**${v.sourceLayer}**) imports '
            '`${v.targetFile}` (**${v.targetLayer}**). ${v.rule}';
      });
      b.writeln();
    }

    if (newCycles.isNotEmpty) {
      b.writeln('### New circular dependencies');
      b.writeln();
      _writeCapped(b, newCycles, (c) {
        final id = c.scc?.id;
        final chain = c.exampleChain.map((f) => '`$f`').join(' → ');
        return '- ${id != null ? '**Cycle $id** ' : ''}(${c.files.length} files): '
            '$chain';
      });
      b.writeln();
    }

    if (newOversized.isNotEmpty) {
      b.writeln('### Groups over `max_scc_size`');
      b.writeln();
      _writeCapped(b, newOversized, (c) {
        final id = c.scc?.id;
        return '- ${id != null ? '**Cycle $id** ' : ''}has ${c.files.length} files';
      });
      b.writeln();
    }

    if (cycles.isNotEmpty) {
      final mermaid = MermaidExporter.export(
        result: result,
        cycles: cycles,
        scope: 'cycles',
      );
      b
        ..writeln('<details><summary>Dependency graph of all cycles</summary>')
        ..writeln();
      if (mermaid.length <= maxMermaidLength) {
        b.write(mermaid);
      } else {
        b.writeln(
          'The graph is too large to render here. Run '
          '`arch_guard -f html` for the interactive version.',
        );
      }
      b
        ..writeln()
        ..writeln('</details>')
        ..writeln();
    }

    if (baseline != null &&
        (baseline.fixedCycleCount > 0 || baseline.fixedViolationCount > 0)) {
      b
        ..writeln(
          '🎉 ${baseline.fixedCycleCount} cycle group(s) and '
          '${baseline.fixedViolationCount} layer violation(s) from the '
          'baseline are fixed. Run `arch_guard --update-baseline` to lock '
          'this in.',
        )
        ..writeln();
    }

    return b.toString();
  }

  static void _writeCapped<T>(
    StringBuffer b,
    List<T> items,
    String Function(T) line,
  ) {
    for (final item in items.take(maxListedItems)) {
      b.writeln(line(item));
    }
    if (items.length > maxListedItems) {
      b.writeln('- … and ${items.length - maxListedItems} more');
    }
  }
}
