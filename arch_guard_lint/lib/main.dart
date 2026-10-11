/// Analyzer plugin that reports arch_guard layer violations and forbidden
/// package imports as warnings.
///
/// Enable it in `analysis_options.yaml`; see the package README.
library;

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/fixes/allow_layer_import.dart';
import 'src/fixes/remove_directive.dart';
import 'src/forbidden_package_rule.dart';
import 'src/layer_violation_rule.dart';

/// Entry point the Dart analysis server looks up.
final plugin = ArchGuardPlugin();

/// Reports arch_guard rules (from `arch_guard.yaml`) as analyzer warnings.
class ArchGuardPlugin extends Plugin {
  /// Creates the plugin; the analysis server uses [plugin].
  ArchGuardPlugin();

  @override
  String get name => 'arch_guard';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(LayerViolationRule());
    registry.registerWarningRule(ForbiddenPackageRule());
    registry.registerFixForRule(LayerViolationRule.code, RemoveDirective.new);
    registry.registerFixForRule(LayerViolationRule.code, AllowLayerImport.new);
    registry.registerFixForRule(ForbiddenPackageRule.code, RemoveDirective.new);
  }
}
