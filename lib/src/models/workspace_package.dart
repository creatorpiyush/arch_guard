/// Represents a package in a Dart 3.5+ workspace or monorepo.
class WorkspacePackage {
  /// Package name (from pubspec.yaml `name:` field).
  final String name;

  /// Relative path to package directory from repository root (e.g. `packages/auth_service`).
  final String packagePath;

  /// Relative path to `lib/` directory from repository root (e.g. `packages/auth_service/lib`).
  final String libPath;

  /// Creates a workspace member package.
  const WorkspacePackage({
    required this.name,
    required this.packagePath,
    required this.libPath,
  });

  @override
  String toString() => 'WorkspacePackage($name @ $libPath)';
}
