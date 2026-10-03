/// Layer definition for Clean Architecture / Layer boundary rules.
class LayerDefinition {
  /// Layer name, as used in `allowed_imports`.
  final String name;

  /// Glob patterns of the files in this layer.
  final List<String> patterns;

  /// Layers this layer may import, besides itself.
  final List<String> allowedImports;

  /// Creates a layer definition.
  const LayerDefinition({
    required this.name,
    required this.patterns,
    this.allowedImports = const [],
  });

  /// Reads a layer from its `arch_guard.yaml` map (`patterns`, `allowed_imports`).
  factory LayerDefinition.fromYaml(String name, Map map) {
    final patterns =
        (map['patterns'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final allowed =
        (map['allowed_imports'] as List?)?.map((e) => e.toString()).toList() ??
        [];
    return LayerDefinition(
      name: name,
      patterns: patterns,
      allowedImports: allowed,
    );
  }
}
