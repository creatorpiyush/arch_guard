/// Layer definition for Clean Architecture / Layer boundary rules.
class LayerDefinition {
  final String name;
  final List<String> patterns;
  final List<String> allowedImports;

  const LayerDefinition({
    required this.name,
    required this.patterns,
    this.allowedImports = const [],
  });

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
