import '../baseline/baseline.dart';
import '../checker/layer_validator.dart';
import '../checker/metric_validator.dart';
import '../checker/module_validator.dart';
import '../checker/package_validator.dart';
import '../checker/workspace_validator.dart';
import '../graph/graph_diff.dart';
import '../models/cycle.dart';
import '../models/file_metrics.dart';
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

  /// Renders the report as Markdown, listing problems not in [baseline] first.
  ///
  /// [since] and [changedFileCount] add a note that the lists only hold
  /// problems touching files changed since that git ref. A non-empty
  /// [graphDiff] adds the advisory "What this change adds" section. With
  /// [churn] (commits per file since [churnSince]), the hotspot table gets a
  /// Commits column.
  static String export({
    required ScanResult result,
    required List<Cycle> cycles,
    List<LayerViolation> layerViolations = const [],
    List<PackageViolation> packageViolations = const [],
    List<MetricViolation> metricViolations = const [],
    List<FileMetrics> hotspots = const [],
    List<WorkspaceViolation> workspaceViolations = const [],
    List<ModuleViolation> moduleViolations = const [],
    BaselineComparison? baseline,
    List<Cycle> oversizedCycles = const [],
    int? maxSccSize,
    String? since,
    int? changedFileCount,
    List<String>? unusedFiles,
    bool failOnUnusedFiles = false,
    GraphDiff? graphDiff,
    Map<String, int>? churn,
    String? churnSince,
  }) {
    final comparison =
        baseline ??
        BaselineComparison.allNew(
          cycles: cycles,
          layerViolations: layerViolations,
          packageViolations: packageViolations,
          metricViolations: metricViolations,
          workspaceViolations: workspaceViolations,
          moduleViolations: moduleViolations,
          unusedFiles: unusedFiles ?? const [],
        );
    final newUnused = comparison.newUnusedFiles;
    final newCycles = comparison.newCycles;
    final newViolations = comparison.newViolations;
    final newPackages = comparison.newPackageViolations;
    final newMetrics = comparison.newMetricViolations;
    final newWorkspace = comparison.newWorkspaceViolations;
    final newModules = comparison.newModuleViolations;
    final newOversized = oversizedCycles.where(comparison.isNewCycle).toList();
    final hasNew =
        newCycles.isNotEmpty ||
        newViolations.isNotEmpty ||
        newPackages.isNotEmpty ||
        newMetrics.isNotEmpty ||
        newWorkspace.isNotEmpty ||
        newModules.isNotEmpty ||
        newOversized.isNotEmpty ||
        (failOnUnusedFiles && newUnused.isNotEmpty);

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
    } else if (cycles.isEmpty &&
        layerViolations.isEmpty &&
        packageViolations.isEmpty &&
        metricViolations.isEmpty &&
        workspaceViolations.isEmpty &&
        moduleViolations.isEmpty) {
      b.writeln('✅ **No circular dependencies or layer violations.**');
    } else {
      b.writeln(
        '✅ **No new architecture problems.** Known problems are '
        'listed in the baseline.',
      );
    }
    b.writeln();
    if (since != null) {
      b
        ..writeln(
          '_Only problems touching ${changedFileCount ?? 0} file(s) changed '
          'since `$since`._',
        )
        ..writeln();
    }

    b
      ..writeln('| | Total | New |')
      ..writeln('| :--- | ---: | ---: |')
      ..writeln(
        '| Circular dependency groups | ${cycles.length} | ${newCycles.length} |',
      )
      ..writeln(
        '| Layer violations | ${layerViolations.length} | '
        '${newViolations.length} |',
      )
      ..writeln(
        '| Forbidden package imports | ${packageViolations.length} | '
        '${newPackages.length} |',
      );
    // Only for projects that use these rules, so other reports stay as before.
    if (metricViolations.isNotEmpty ||
        (baseline?.fixedMetricViolationCount ?? 0) > 0) {
      b.writeln(
        '| Metric limit violations | ${metricViolations.length} | '
        '${newMetrics.length} |',
      );
    }
    if (workspaceViolations.isNotEmpty ||
        (baseline?.fixedWorkspaceViolationCount ?? 0) > 0) {
      b.writeln(
        '| Workspace rule violations | ${workspaceViolations.length} | '
        '${newWorkspace.length} |',
      );
    }
    if (moduleViolations.isNotEmpty ||
        (baseline?.fixedModuleViolationCount ?? 0) > 0) {
      b.writeln(
        '| Module boundary violations | ${moduleViolations.length} | '
        '${newModules.length} |',
      );
    }
    // null: the check is off, so the row is left out.
    if (unusedFiles != null) {
      b.writeln(
        '| Unused files | ${unusedFiles.length} | ${newUnused.length} |',
      );
    }
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
            '`${v.targetFile}` (**${v.targetLayer}**)${v.viaSuffix}. ${v.rule}';
      });
      b.writeln();
    }

    if (newPackages.isNotEmpty) {
      b.writeln('### New forbidden package imports');
      b.writeln();
      _writeCapped(b, newPackages, (v) {
        final at = v.line != null ? ':${v.line}' : '';
        return '- `${v.sourceFile}$at` imports `${v.uri}`. ${v.rule}';
      });
      b.writeln();
    }

    if (newWorkspace.isNotEmpty) {
      b.writeln('### New workspace rule violations');
      b.writeln();
      _writeCapped(b, newWorkspace, (v) {
        final at = v.line != null ? ':${v.line}' : '';
        return '- `${v.sourceFile}$at` (**${v.sourcePackage}**) imports '
            '`${v.targetFile}` (**${v.targetPackage}**). ${v.rule}';
      });
      b.writeln();
    }

    if (newModules.isNotEmpty) {
      b.writeln('### New module boundary violations');
      b.writeln();
      _writeCapped(b, newModules, (v) {
        final at = v.line != null ? ':${v.line}' : '';
        return '- `${v.sourceFile}$at` (**${v.sourceModule}**) imports '
            '`${v.targetFile}` (**${v.targetModule}**). ${v.rule}';
      });
      b.writeln();
    }

    if (newMetrics.isNotEmpty) {
      b.writeln('### New metric limit violations');
      b.writeln();
      _writeCapped(b, newMetrics, (v) => '- ${v.rule}');
      b.writeln();
    }

    if (newCycles.isNotEmpty) {
      b.writeln('### New circular dependencies');
      b.writeln();
      _writeCapped(b, newCycles, (c) {
        final id = c.scc?.id;
        final chain = c.exampleChain.map((f) => '`$f`').join(' → ');
        final hint = c.scc?.suggestedBreak;
        final fix = hint == null
            ? ''
            : ' Suggested fix: remove `${hint.from}'
                  '${hint.line != null ? ':${hint.line}' : ''}` → `${hint.to}`'
                  '${hint.breaksCycle ? '' : ' (shrinks it to ${hint.remainingLargestCycle} files)'}.';
        final reason = comparison.newCycleReasons[c];
        return '- ${id != null ? '**Cycle $id** ' : ''}(${c.files.length} files): '
            '$chain${c.platformNote}$fix${reason == null ? '' : ' Why new: $reason.'}';
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

    if (newUnused.isNotEmpty) {
      b.writeln('### New unused files');
      b.writeln();
      b.writeln(
        'No entry point imports these, directly or indirectly. Delete them, '
        'or add the file that uses them under `unused_files: entry_points`.',
      );
      b.writeln();
      _writeCapped(b, newUnused, (f) => '- `$f`');
      b.writeln();
    }

    if (graphDiff != null && !graphDiff.isEmpty) _writeDiff(b, graphDiff);

    if (hotspots.isNotEmpty) {
      if (churn == null) {
        b
          ..writeln('<details><summary>Most coupled files</summary>')
          ..writeln()
          ..writeln('| File | Fan-in | Fan-out | Instability |')
          ..writeln('| :--- | ---: | ---: | ---: |');
      } else {
        b
          ..writeln(
            '<details><summary>Most coupled files, changed most since '
            '`$churnSince`</summary>',
          )
          ..writeln()
          ..writeln('| File | Commits | Fan-in | Fan-out | Instability |')
          ..writeln('| :--- | ---: | ---: | ---: | ---: |');
      }
      for (final m in hotspots) {
        final commits = churn == null ? '' : ' ${churn[m.file] ?? 0} |';
        b.writeln(
          '| `${m.file}` |$commits ${m.fanIn} | ${m.fanOut} | '
          '${m.instability} |',
        );
      }
      b
        ..writeln()
        ..writeln('</details>')
        ..writeln();
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
        (baseline.fixedCycleCount > 0 ||
            baseline.fixedViolationCount > 0 ||
            baseline.fixedPackageViolationCount > 0 ||
            baseline.fixedMetricViolationCount > 0 ||
            baseline.fixedWorkspaceViolationCount > 0 ||
            baseline.fixedModuleViolationCount > 0 ||
            baseline.fixedUnusedFileCount > 0)) {
      final fixed = _andJoin([
        '${baseline.fixedCycleCount} cycle group(s)',
        '${baseline.fixedViolationCount} layer violation(s)',
        '${baseline.fixedPackageViolationCount} forbidden package import(s)',
        if (baseline.fixedMetricViolationCount > 0)
          '${baseline.fixedMetricViolationCount} metric limit violation(s)',
        if (baseline.fixedWorkspaceViolationCount > 0)
          '${baseline.fixedWorkspaceViolationCount} workspace rule '
              'violation(s)',
        if (baseline.fixedModuleViolationCount > 0)
          '${baseline.fixedModuleViolationCount} module boundary '
              'violation(s)',
        if (baseline.fixedUnusedFileCount > 0)
          '${baseline.fixedUnusedFileCount} unused file(s)',
      ]);
      b
        ..writeln(
          '🎉 $fixed from the baseline are fixed. Run `arch_guard --update-baseline` to lock '
          'this in.',
        )
        ..writeln();
    }
    if (baseline != null && baseline.improvements.isNotEmpty) {
      b
        ..writeln(
          '📉 ${baseline.improvements.join(', ')} since the baseline. Run '
          '`arch_guard --update-baseline` to lock this in.',
        )
        ..writeln();
    }

    return b.toString();
  }

  /// Most imports listed under one new group edge.
  static const maxImportsPerEdge = 5;

  static void _writeDiff(StringBuffer b, GraphDiff diff) {
    b
      ..writeln('### What this change adds')
      ..writeln()
      ..writeln('_Advice only: this does not affect the result._')
      ..writeln();
    const edgeTitles = {
      'layer': 'New layer dependencies',
      'module': 'New module dependencies',
      'member': 'New workspace member dependencies',
    };
    for (final MapEntry(key: kind, value: title) in edgeTitles.entries) {
      final edges = diff.groupEdges.where((e) => e.kind == kind).toList();
      if (edges.isEmpty) continue;
      b
        ..writeln('**$title**')
        ..writeln();
      _writeCapped(b, edges, (e) {
        final n = e.imports.length;
        final lines = [
          '- `${e.from}` → `${e.to}` ($n import${n == 1 ? '' : 's'})',
          for (final i in e.imports.take(maxImportsPerEdge))
            '  - `${i.from}${i.line == null ? '' : ':${i.line}'}` → `${i.to}`',
          if (n > maxImportsPerEdge) '  - … and ${n - maxImportsPerEdge} more',
        ];
        return lines.join('\n');
      });
      b.writeln();
    }
    if (diff.packages.isNotEmpty) {
      const suffix = {'module': ' (module)', 'member': ' (workspace member)'};
      b
        ..writeln('**New packages**')
        ..writeln();
      _writeCapped(
        b,
        diff.packages,
        (p) => '- `${p.group}`${suffix[p.kind] ?? ''}: `${p.package}`',
      );
      b.writeln();
    }
    if (diff.coupling.isNotEmpty) {
      b
        ..writeln('**Coupling growth**')
        ..writeln();
      for (final c in diff.coupling) {
        b.writeln(
          '- `${c.file}`: ${[if (c.fanInAfter != c.fanInBefore) 'fan-in ${c.fanInBefore} → ${c.fanInAfter}', if (c.fanOutAfter != c.fanOutBefore) 'fan-out ${c.fanOutBefore} → ${c.fanOutAfter}'].join(', ')}',
        );
      }
      b.writeln();
    }
  }

  static String _andJoin(List<String> parts) =>
      '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';

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
