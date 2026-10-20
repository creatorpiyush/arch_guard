import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:arch_guard/arch_guard.dart';

import 'project_rules.dart';

/// Warns when an import crosses a layer boundary that `arch_guard.yaml`
/// does not allow.
class LayerViolationRule extends AnalysisRule {
  /// The diagnostic; `static const` so `// ignore:` comments match it.
  static const LintCode code = LintCode(
    'layer_violation',
    '{0}',
    correctionMessage: '{1}',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  LayerViolationRule()
    : super(
        name: 'layer_violation',
        description:
            'Imports must respect the layer rules (allowed_imports) in '
            'arch_guard.yaml.',
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
    registry.addPartDirective(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AnalysisRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitImportDirective(ImportDirective node) {
    _check(node.uri, node.libraryImport?.uri);
    _checkConfigurations(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _check(node.uri, node.libraryExport?.uri);
    _checkConfigurations(node);
  }

  @override
  void visitPartDirective(PartDirective node) {
    _check(node.uri, node.partInclude?.uri);
  }

  // `import 'a.dart' if (dart.library.io) 'b.dart'`: every URI may be the
  // one compiled on some platform, so each is checked.
  void _checkConfigurations(NamespaceDirective node) {
    for (final c in node.configurations) {
      _check(c.uri, c.resolvedUri);
    }
  }

  void _check(StringLiteral uriNode, DirectiveUri? target) {
    if (target is! DirectiveUriWithSource) return;
    final rules = ProjectRules.of(context);
    if (rules == null) return;
    final unit = context.currentUnit ?? context.definingUnit;
    final from = rules.relative(unit.file.path);
    final to = rules.relative(target.source.fullName);
    if (from == null ||
        to == null ||
        rules.isIgnored(from) ||
        rules.isIgnored(to)) {
      return;
    }

    _report(uriNode, rules, rules.checkLayer(from, to));

    // A barrel in no layer is never checked itself, so follow its re-exports
    // to the first libraries that have a layer, as the CLI does.
    if (target is! DirectiveUriWithLibrary ||
        rules.layerOf(from) == null ||
        rules.layerOf(to) != null) {
      return;
    }
    final seen = {to};
    void follow(LibraryElement barrel, List<String> via) {
      for (final next in barrel.exportedLibraries) {
        final path = rules.relative(next.firstFragment.source.fullName);
        if (path == null || rules.isIgnored(path) || !seen.add(path)) continue;
        if (rules.layerOf(path) == null) {
          follow(next, [...via, path]);
          continue;
        }
        _report(uriNode, rules, rules.checkLayer(from, path, via: via));
      }
    }

    follow(target.library, [to]);
  }

  void _report(StringLiteral uriNode, ProjectRules rules, LayerViolation? v) {
    if (v == null || rules.isKnownLayerViolation(v)) return;
    rule.reportAtNode(
      uriNode,
      arguments: [
        'Layer `${v.sourceLayer}` imports `${v.targetFile}` from layer '
            '`${v.targetLayer}`${v.viaSuffix}. ${v.rule}',
        v.suggestion,
      ],
    );
  }
}
