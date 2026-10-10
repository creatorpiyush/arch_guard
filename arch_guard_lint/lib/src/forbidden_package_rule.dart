import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:arch_guard/arch_guard.dart';

import 'project_rules.dart';

/// Warns on imports of packages or core libraries ruled out by
/// `forbidden_packages` in `arch_guard.yaml`.
class ForbiddenPackageRule extends AnalysisRule {
  /// The diagnostic; `static const` so `// ignore:` comments match it.
  static const LintCode code = LintCode(
    'forbidden_package',
    '{0}',
    correctionMessage: '{1}',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  ForbiddenPackageRule()
    : super(
        name: 'forbidden_package',
        description:
            'Imports must not use packages listed under forbidden_packages in '
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
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    final rules = ProjectRules.of(context);
    if (rules == null) return;
    final unit = context.currentUnit ?? context.definingUnit;
    final from = rules.relative(unit.file.path);
    if (from == null || rules.isIgnored(from)) return;

    final libraryUri = context.libraryElement?.uri;
    final ownPackage = libraryUri?.scheme == 'package'
        ? libraryUri!.pathSegments.first
        : null;

    for (final uriNode in [
      node.uri,
      for (final c in node.configurations) c.uri,
    ]) {
      final uri = uriNode.stringValue;
      if (uri == null || PackageImport.packageOf(uri) == ownPackage) continue;
      final v = rules.checkPackage(from, uri);
      if (v == null || rules.isKnownPackageViolation(v)) continue;
      rule.reportAtNode(uriNode, arguments: [v.rule, v.suggestion]);
    }
  }
}
