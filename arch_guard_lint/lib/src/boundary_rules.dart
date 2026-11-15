import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'project_rules.dart';

/// Warns when an import between workspace members breaks `workspace_rules`.
class WorkspaceViolationRule extends _FileToFileRule {
  /// The diagnostic; `static const` so `// ignore:` comments match it.
  static const LintCode code = LintCode(
    'workspace_violation',
    '{0}',
    correctionMessage: '{1}',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  WorkspaceViolationRule()
    : super(
        name: 'workspace_violation',
        description:
            'Imports between workspace members must respect workspace_rules '
            'in arch_guard.yaml.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  List<String>? check(ProjectRules rules, String from, String to) {
    final v = rules.checkWorkspace(from, to);
    if (v == null || rules.isKnownWorkspaceViolation(v)) return null;
    return [
      '`${v.sourcePackage}` imports `${v.targetFile}` from workspace member '
          '`${v.targetPackage}`. ${v.rule}',
      v.suggestion,
    ];
  }
}

/// Warns when an import crosses a module boundary that `modules:` forbids.
class ModuleViolationRule extends _FileToFileRule {
  /// The diagnostic; `static const` so `// ignore:` comments match it.
  static const LintCode code = LintCode(
    'module_violation',
    '{0}',
    correctionMessage: '{1}',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Creates the rule.
  ModuleViolationRule()
    : super(
        name: 'module_violation',
        description:
            'Imports between modules must go through public files and respect '
            '`modules: allowed` in arch_guard.yaml.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  List<String>? check(ProjectRules rules, String from, String to) {
    final v = rules.checkModule(from, to);
    if (v == null || rules.isKnownModuleViolation(v)) return null;
    return [
      'Module `${v.sourceModule}` imports `${v.targetFile}` from module '
          '`${v.targetModule}`. ${v.rule}',
      v.suggestion,
    ];
  }
}

/// A rule that checks every directive (and conditional URI) from the
/// current file to another project file.
abstract class _FileToFileRule extends AnalysisRule {
  _FileToFileRule({required super.name, required super.description});

  /// The message and correction for an import of [to] by [from], or `null`
  /// when it is fine. Both paths are relative to the config folder.
  List<String>? check(ProjectRules rules, String from, String to);

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
  final _FileToFileRule rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitImportDirective(ImportDirective node) {
    _check(node.uri, node.libraryImport?.uri);
    for (final c in node.configurations) {
      _check(c.uri, c.resolvedUri);
    }
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _check(node.uri, node.libraryExport?.uri);
    for (final c in node.configurations) {
      _check(c.uri, c.resolvedUri);
    }
  }

  @override
  void visitPartDirective(PartDirective node) {
    _check(node.uri, node.partInclude?.uri);
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
    final message = rule.check(rules, from, to);
    if (message != null) rule.reportAtNode(uriNode, arguments: message);
  }
}
