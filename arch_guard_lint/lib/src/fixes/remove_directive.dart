import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Removes the import or export a diagnostic points at. For a conditional
/// URI (`if (dart.library.io) '…'`) only that clause is removed.
class RemoveDirective extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'arch_guard.fix.removeDirective',
    DartFixKindPriority.standard,
    'Remove this {0}',
  );

  /// Creates the fix; the analysis server calls this.
  RemoveDirective({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  List<String> get fixArguments => [
    node.thisOrAncestorOfType<ExportDirective>() != null ? 'export' : 'import',
  ];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final directive = node.thisOrAncestorOfType<NamespaceDirective>();
    if (directive == null) return;
    final configuration = node.thisOrAncestorOfType<Configuration>();
    await builder.addDartFileEdit(file, (b) {
      if (configuration != null) {
        // ` if (dart.library.x) 'uri'`, including the space before `if`.
        final start = configuration.ifKeyword.previous!.end;
        b.addDeletion(SourceRange(start, configuration.end - start));
      } else {
        b.addDeletion(utils.getLinesRange(range.node(directive)));
      }
    });
  }
}
