/// Represents a scanned Dart file in a project.
class FileNode {
  /// Relative path within the package (e.g. `lib/src/auth.dart`).
  final String relativePath;

  /// Absolute path on disk.
  final String absolutePath;

  /// List of raw import URIs extracted from this file.
  final List<String> imports;

  /// List of raw export URIs extracted from this file.
  final List<String> exports;

  const FileNode({
    required this.relativePath,
    required this.absolutePath,
    this.imports = const [],
    this.exports = const [],
  });

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'absolutePath': absolutePath,
    'imports': imports,
    'exports': exports,
  };

  @override
  String toString() => 'FileNode($relativePath)';
}
