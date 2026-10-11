import 'dart:convert';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:arch_guard/arch_guard.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Warns on the one import whose removal breaks (or shrinks most) each
/// circular dependency in the package's `lib/`.
class CircularDependencyRule extends AnalysisRule {
  /// The diagnostic; `static const` so `// ignore:` comments match it.
  static const LintCode code = LintCode(
    'circular_dependency',
    '{0}',
    correctionMessage: '{1}',
    severity: DiagnosticSeverity.WARNING,
  );

  /// How long a computed graph is reused before `lib/` is checked for
  /// changes again.
  static Duration recheckAfter = const Duration(seconds: 2);

  /// Creates the rule.
  CircularDependencyRule()
    : super(
        name: 'circular_dependency',
        description:
            'Files in lib/ must not import each other in a cycle; the import '
            'that breaks the cycle is reported.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addImportDirective(this, visitor);
    registry.addExportDirective(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitImportDirective(ImportDirective node) =>
      _check(node, node.libraryImport?.uri);

  @override
  void visitExportDirective(ExportDirective node) =>
      _check(node, node.libraryExport?.uri);

  void _check(NamespaceDirective node, DirectiveUri? target) {
    if (target is! DirectiveUriWithSource) return;
    final cycles = _PackageCycles.of(context);
    if (cycles == null) return;
    final unit = context.currentUnit ?? context.definingUnit;
    final from = cycles.relative(unit.file.path);
    final hints = cycles.byFile[from];
    if (hints == null) return;
    final to = cycles.relative(target.source.fullName);
    final line = (node.root as CompilationUnit).lineInfo
        .getLocation(node.offset)
        .lineNumber;
    for (final (hint, cycle) in hints) {
      if (hint.to != to || hint.line != line) continue;
      rule.reportAtNode(
        node.uri,
        arguments: [
          'This import closes a circular dependency of '
              '${cycle.files.length} files: ${cycle.exampleChain.join(' -> ')}. '
              'Removing it '
              '${hint.breaksCycle ? 'breaks the cycle' : 'shrinks it to ${hint.remainingLargestCycle} files'}.',
          'Move the code both files need into a third file, or invert the '
              'dependency.',
        ],
      );
    }
  }
}

/// The cycles of one package's `lib/`, cached per package root.
class _PackageCycles {
  final Folder _root;
  final String _key;
  DateTime _checkedAt;

  /// Hints grouped by the importing file (relative `/` path).
  final Map<String, List<(CycleBreak, Cycle)>> byFile;

  _PackageCycles(this._root, this._key, this._checkedAt, this.byFile);

  /// [path] relative to the package root, with `/` separators.
  String relative(String path) {
    final ctx = _root.provider.pathContext;
    return ctx.split(ctx.relative(path, from: _root.path)).join('/');
  }

  // Keyed by provider so in-memory test providers never share entries.
  static final _cache = Expando<Map<String, _PackageCycles>>();

  static _PackageCycles? of(RuleContext context) {
    if (!context.isInLibDir) return null;
    final root = context.package?.root;
    if (root == null) return null;
    final byPath = _cache[root.provider] ??= {};
    final cached = byPath[root.path];
    final now = DateTime.now();
    if (cached != null &&
        now.difference(cached._checkedAt) <
            CircularDependencyRule.recheckAfter) {
      return cached;
    }
    try {
      // ponytail: walks lib/ at most every recheckAfter, O(files) per check.
      // Upgrade path: invalidate from the analysis server's change events.
      final files = _dartFiles(root);
      final key = [
        for (final f in files) '${f.path}:${f.modificationStamp}',
      ].join('|');
      if (cached != null && cached._key == key) {
        cached._checkedAt = now;
        return cached;
      }
      return byPath[root.path] = _compute(root, files, key, now);
    } catch (_) {
      // Never let a problem here throw inside the analysis server.
      return null;
    }
  }

  static List<File> _dartFiles(Folder root) {
    final config = ArchGuardConfig.loadWith(root.path, (name) {
      final f = _file(root, name);
      return f.exists ? f.readAsStringSync() : null;
    });
    final excludes = [
      for (final g in [...defaultExcludePatterns, ...config.ignorePatterns])
        Glob(g, context: p.posix),
    ];
    final ctx = root.provider.pathContext;
    final files = <File>[];
    void walk(Folder folder) {
      for (final child in folder.getChildren()) {
        if (child is Folder) {
          walk(child);
        } else if (child is File && child.path.endsWith('.dart')) {
          final rel = ctx
              .split(ctx.relative(child.path, from: root.path))
              .join('/');
          if (!excludes.any((g) => g.matches(rel))) files.add(child);
        }
      }
    }

    final lib = _folder(root, 'lib');
    if (lib.exists) walk(lib);
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static _PackageCycles _compute(
    Folder root,
    List<File> files,
    String key,
    DateTime now,
  ) {
    final ctx = root.provider.pathContext;
    String rel(String path) =>
        ctx.split(ctx.relative(path, from: root.path)).join('/');
    final pubspec = _file(root, 'pubspec.yaml');
    final doc = pubspec.exists ? loadYaml(pubspec.readAsStringSync()) : null;
    final name = doc is Map && doc['name'] is String
        ? doc['name'] as String
        : root.shortName;

    final scan = ProjectScanner.scanSources(
      packageName: name,
      sources: {for (final f in files) rel(f.path): f.readAsStringSync()},
    );
    var cycles = DependencyGraph.fromScanResult(
      scan,
    ).findCircularDependencies();

    final baselineFile = _file(root, defaultBaselineFileName);
    if (baselineFile.exists) {
      try {
        cycles = Baseline.fromJson(
          jsonDecode(baselineFile.readAsStringSync()),
        ).compare(cycles: cycles, layerViolations: const []).newCycles;
      } catch (_) {
        // A broken baseline is reported by the CLI; ignore it here.
      }
    }

    final byFile = <String, List<(CycleBreak, Cycle)>>{};
    for (final cycle in cycles) {
      final hint = cycle.scc?.suggestedBreak;
      if (hint != null) (byFile[hint.from] ??= []).add((hint, cycle));
    }
    return _PackageCycles(root, key, now, byFile);
  }

  // `Folder.getFile`/`getFolder` only exist from analyzer 14.
  static File _file(Folder folder, String name) => folder.provider.getFile(
    folder.provider.pathContext.join(folder.path, name),
  );

  static Folder _folder(Folder folder, String name) => folder.provider
      .getFolder(folder.provider.pathContext.join(folder.path, name));
}
