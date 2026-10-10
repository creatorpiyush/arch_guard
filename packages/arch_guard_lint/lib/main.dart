import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/layer_violation_rule.dart';

/// Entry point the Dart analysis server looks up.
final plugin = ArchGuardPlugin();

/// Reports arch_guard rules (from `arch_guard.yaml`) as analyzer warnings.
class ArchGuardPlugin extends Plugin {
  @override
  String get name => 'arch_guard';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(LayerViolationRule());
  }
}
