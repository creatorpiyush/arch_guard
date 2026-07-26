/// Default glob patterns for files and directories that should be excluded from import scanning.
const List<String> defaultExcludePatterns = [
  '**/*.g.dart',
  '**/*.freezed.dart',
  '**/*.mocks.dart',
  '**/*.template.dart',
  '**/.dart_tool/**',
  '**/build/**',
  "**/stubs/**",
  "**/stub/**",
];
