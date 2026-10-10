import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/config_model.dart';
import '../models/scan_result.dart';
import '../models/workspace_package.dart';

/// An import between workspace members that `workspace_rules` doesn't allow.
class WorkspaceViolation {
  /// Path of the importing file.
  final String sourceFile;

  /// Path of the imported file.
  final String targetFile;

  /// Name of the member [sourceFile] belongs to.
  final String sourcePackage;

  /// Name of the member [targetFile] belongs to.
  final String targetPackage;

  /// The `workspace_rules` selector that applied to [sourcePackage].
  final String selector;

  /// Members the selector allows.
  final List<String> allowed;

  /// 1-based line of the directive in [sourceFile], if known.
  final int? line;

  /// Creates a violation.
  const WorkspaceViolation({
    required this.sourceFile,
    required this.targetFile,
    required this.sourcePackage,
    required this.targetPackage,
    required this.selector,
    this.allowed = const [],
    this.line,
  });

  /// The broken rule.
  String get rule => allowed.isEmpty
      ? '`$sourcePackage` (rule `$selector`) may not import other workspace '
            'members.'
      : '`$sourcePackage` (rule `$selector`) may only import members matching '
            '${allowed.map((a) => '`$a`').join(', ')}.';

  /// How to resolve it.
  String get suggestion =>
      'Move the shared code into a member `$sourcePackage` may import, invert '
      'the dependency, or, if intended, add `$targetPackage` to the `allowed` '
      'list of `$selector`.';

  /// JSON form used by the JSON exporter.
  Map<String, dynamic> toJson() => {
    'sourceFile': sourceFile,
    'targetFile': targetFile,
    'sourcePackage': sourcePackage,
    'targetPackage': targetPackage,
    'selector': selector,
    'allowed': allowed,
    'line': ?line,
  };

  @override
  String toString() =>
      '❌ Workspace Violation: [$sourcePackage] $sourceFile'
      '${line != null ? ':$line' : ''} -> [$targetPackage] $targetFile';
}

/// Checks imports between workspace members against `workspace_rules`.
class WorkspaceValidator {
  /// Validates cross-member edges in [result] against [config].
  static List<WorkspaceViolation> validate({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    if (config.workspaceRules.isEmpty || result.packages.isEmpty) {
      return const [];
    }
    final memberOf = _memberResolver(result.packages);
    final rules = [
      for (final MapEntry(:key, :value) in config.workspaceRules.entries)
        (
          selector: key,
          glob: _glob(key),
          allowed: value,
          allowedGlobs: value.map(_glob).toList(),
        ),
    ];

    final violations = <WorkspaceViolation>[];
    for (final edge in result.edges) {
      final from = memberOf(edge.from);
      final to = memberOf(edge.to);
      if (from == null || to == null || from.name == to.name) continue;
      final rule = rules.where((r) => _matches(r.glob, from)).firstOrNull;
      if (rule == null || rule.allowedGlobs.any((g) => _matches(g, to))) {
        continue;
      }
      violations.add(
        WorkspaceViolation(
          sourceFile: edge.from,
          targetFile: edge.to,
          sourcePackage: from.name,
          targetPackage: to.name,
          selector: rule.selector,
          allowed: rule.allowed,
          line: edge.line,
        ),
      );
    }
    return violations;
  }

  /// Selectors and `allowed` entries that match no member (likely typos).
  static List<String> unmatchedPatterns({
    required ScanResult result,
    required ArchGuardConfig config,
  }) {
    final seen = <String>{};
    return [
      for (final MapEntry(:key, :value) in config.workspaceRules.entries)
        for (final pattern in [key, ...value])
          if (seen.add(pattern) &&
              !result.packages.any((m) => _matches(_glob(pattern), m)))
            pattern,
    ];
  }

  static Glob _glob(String pattern) => Glob(pattern, context: p.posix);

  static bool _matches(Glob glob, WorkspacePackage m) =>
      glob.matches(m.packagePath) || glob.matches(m.name);

  /// Longest `packagePath/` prefix wins; root (`.`) owns everything else.
  static WorkspacePackage? Function(String) _memberResolver(
    List<WorkspacePackage> members,
  ) {
    final byLength = [
      for (final m in members)
        if (m.packagePath != '.') m,
    ]..sort((a, b) => b.packagePath.length.compareTo(a.packagePath.length));
    final root = members.where((m) => m.packagePath == '.').firstOrNull;
    final cache = <String, WorkspacePackage?>{};
    return (file) => cache.putIfAbsent(
      file,
      () =>
          byLength
              .where((m) => file.startsWith('${m.packagePath}/'))
              .firstOrNull ??
          root,
    );
  }
}
