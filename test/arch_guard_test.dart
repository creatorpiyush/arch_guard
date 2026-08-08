import 'package:arch_guard/arch_guard.dart';
import 'package:test/test.dart';

void main() {
  test('public library exports essential classes', () {
    expect(ProjectScanner, isNotNull);
    expect(DependencyGraph, isNotNull);
    expect(DotExporter, isNotNull);
    expect(HtmlExporter, isNotNull);
  });
}
