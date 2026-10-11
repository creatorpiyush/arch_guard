import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

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

    final v = rules.checkLayer(from, to);
    if (v == null || rules.isKnownLayerViolation(v)) return;
    rule.reportAtNode(
      uriNode,
      arguments: [
        'Layer `${v.sourceLayer}` imports `${v.targetFile}` from layer '
            '`${v.targetLayer}`. ${v.rule}',
        v.suggestion,
      ],
    );
  }
}
