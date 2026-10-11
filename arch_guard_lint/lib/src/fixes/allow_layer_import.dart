import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../project_rules.dart';

/// [yaml] with [target] added to `layers: <layer>: allowed_imports`, under
/// [section] (`arch_guard` or `dep_graph_visualizer` in `pubspec.yaml`) when
/// given. [currentAllowed] is the layer's effective list, preset included,
/// used when the layer isn't listed yet. Returns `null` when [yaml] can't be
/// edited.
String? allowLayerImportYaml(
  String yaml, {
  required String layer,
  required String target,
  required List<String> currentAllowed,
  String? section,
}) {
  try {
    final editor = YamlEditor(yaml);
    final base = [?section];
    Object? at(List<Object> path) {
      try {
        return editor.parseAt(path).value;
      } catch (_) {
        return null;
      }
    }

    YamlNode flow(List<String> list) =>
        wrapAsYamlNode(list, collectionStyle: CollectionStyle.FLOW);
    final allowed = [...currentAllowed, target];
    final listPath = [...base, 'layers', layer, 'allowed_imports'];
    if (at(listPath) is List) {
      editor.appendToList(listPath, target);
    } else if (at([...base, 'layers', layer]) is Map) {
      editor.update(listPath, flow(allowed));
    } else if (at([...base, 'layers']) is Map) {
      // Block style here: yaml_edit emits invalid YAML for a flow list
      // nested in new block maps.
      editor.update([...base, 'layers', layer], {'allowed_imports': allowed});
    } else {
      editor.update(
        [...base, 'layers'],
        {
          layer: {'allowed_imports': allowed},
        },
      );
    }
    return editor.toString();
  } catch (_) {
    return null;
  }
}

/// Adds the imported layer to the importing layer's `allowed_imports`, in
/// whichever file the configuration came from.
class AllowLayerImport extends ResolvedCorrectionProducer {
  static const _kind = FixKind(
    'arch_guard.fix.allowLayerImport',
    DartFixKindPriority.standard - 1,
    'Allow layer `{0}` to import `{1}` ({2})',
  );

  /// Creates the fix; the analysis server calls this.
  AllowLayerImport({required super.context});

  List<String>? _arguments;

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  List<String>? get fixArguments => _arguments;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final rules = ProjectRules.forFile(resourceProvider, file);
    final configPath = rules?.config.sourcePath;
    if (rules == null || configPath == null) return;

    final configuration = node.thisOrAncestorOfType<Configuration>();
    final directive = node.thisOrAncestorOfType<NamespaceDirective>();
    final target = configuration != null
        ? configuration.resolvedUri
        : switch (directive) {
            ImportDirective d => d.libraryImport?.uri,
            ExportDirective d => d.libraryExport?.uri,
            _ => null,
          };
    if (target is! DirectiveUriWithSource) return;
    final from = rules.relative(file);
    final to = rules.relative(target.source.fullName);
    if (from == null || to == null) return;
    final v = rules.checkLayer(from, to);
    if (v == null) return;

    final configFile = resourceProvider.getFile(configPath);
    if (!configFile.exists) return;
    final old = configFile.readAsStringSync();
    final isPubspec = configFile.shortName == 'pubspec.yaml';
    String? section;
    if (isPubspec) {
      final doc = loadYaml(old);
      section = doc is Map && doc.containsKey('arch_guard')
          ? 'arch_guard'
          : 'dep_graph_visualizer';
    }
    final updated = allowLayerImportYaml(
      old,
      section: section,
      layer: v.sourceLayer,
      target: v.targetLayer,
      currentAllowed: rules.config.layers[v.sourceLayer]?.allowedImports ?? [],
    );
    if (updated == null || updated == old) return;

    _arguments = [v.sourceLayer, v.targetLayer, configFile.shortName];
    await builder.addYamlFileEdit(
      configPath,
      (b) => b.addSimpleReplacement(SourceRange(0, old.length), updated),
    );
  }
}
