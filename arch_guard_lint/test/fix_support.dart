import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

/// Runs [fix] for the first diagnostic of the rule under test in [path].
///
/// Returns the new content of every file the fix edits, keyed by path, and
/// the fix's message.
Future<(Map<String, String>, String?)> applyFix(
  AnalysisRuleTest t,
  String path,
  CorrectionProducer Function({required CorrectionProducerContext context}) fix,
) async {
  final unit = await t.resolveFile(t.convertPath(path));
  final library =
      await unit.session.getResolvedLibrary(unit.path) as ResolvedLibraryResult;
  final diagnostic = unit.diagnostics.firstWhere(
    // `name` is deprecated in analyzer 14; its replacement isn't in 9.
    // ignore: deprecated_member_use
    (d) => d.diagnosticCode.name.toLowerCase() == t.rule.name.toLowerCase(),
  );
  final producer = fix(
    context: CorrectionProducerContext.createResolved(
      libraryResult: library,
      unitResult: unit,
      diagnostic: diagnostic,
      selectionOffset: diagnostic.offset,
      selectionLength: diagnostic.length,
    ),
  );
  final builder = ChangeBuilder(session: unit.session);
  await producer.compute(builder);
  final kind = producer.fixKind;
  final args = producer.fixArguments ?? const [];
  var message = kind?.message;
  for (var i = 0; i < args.length; i++) {
    message = message?.replaceAll('{$i}', args[i]);
  }
  return (
    {
      for (final edit in builder.sourceChange.edits)
        edit.file: SourceEdit.applySequence(
          t.resourceProvider.getFile(edit.file).exists
              ? t.resourceProvider.getFile(edit.file).readAsStringSync()
              : '',
          edit.edits,
        ),
    },
    message,
  );
}
