import 'dart:convert';
import 'dart:io';

/// Maintainer utility to fetch vis-network standalone JS from unpkg
/// and regenerate `lib/src/assets/vis_network_asset.dart`.
///
/// Usage:
/// ```bash
/// dart run tool/bundle_vis_network.dart
/// ```
void main() async {
  const version = '10.1.0';
  final url = Uri.parse(
    'https://unpkg.com/vis-network@$version/standalone/umd/vis-network.min.js',
  );

  print('Fetching vis-network v$version from unpkg...');
  final client = HttpClient();
  final request = await client.getUrl(url);
  final response = await request.close();

  if (response.statusCode != 200) {
    print('Failed to download JS file: HTTP ${response.statusCode}');
    exit(1);
  }

  final bytes = await response.fold<List<int>>(
    <int>[],
    (previous, element) => previous..addAll(element),
  );
  client.close();

  final base64Str = base64Encode(bytes);
  print('Downloaded ${bytes.length} bytes. Base64 length: ${base64Str.length}');

  final buffer = StringBuffer();
  buffer.writeln("import 'dart:convert';");
  buffer.writeln();
  buffer.writeln("// GENERATED FILE. Do not edit by hand.");
  buffer.writeln("//");
  buffer.writeln(
    "// Bundled copy of vis-network (standalone UMD, minified build) for use with",
  );
  buffer.writeln(
    "// the --offline flag, so the interactive HTML report renders without any",
  );
  buffer.writeln(
    "// outbound network access (air-gapped CI runners, sandboxed environments).",
  );
  buffer.writeln("//");
  buffer.writeln(
    "// vis-network is dual-licensed under the Apache-2.0 and MIT licenses.",
  );
  buffer.writeln("// Source: https://github.com/visjs/vis-network");
  buffer.writeln(
    "// Bundled from npm package vis-network $version (standalone/umd/vis-network.min.js).",
  );
  buffer.writeln();
  buffer.writeln(
    "/// Base64-encoded contents of vis-network.min.js (standalone UMD build).",
  );
  buffer.writeln("///");
  buffer.writeln(
    "/// Decode with [visNetworkMinJs] rather than using this constant directly.",
  );
  buffer.writeln("const String visNetworkMinJsBase64 =");

  const chunkSize = 2000;
  for (var i = 0; i < base64Str.length; i += chunkSize) {
    final end = (i + chunkSize < base64Str.length)
        ? i + chunkSize
        : base64Str.length;
    final chunk = base64Str.substring(i, end);
    final isLast = end == base64Str.length;
    buffer.writeln("    '$chunk'${isLast ? ';' : ''}");
  }

  buffer.writeln();
  buffer.writeln(
    "/// Decoded JS source of the bundled vis-network standalone UMD build.",
  );
  buffer.writeln("///");
  buffer.writeln(
    "/// Decoded lazily and cached on first access, since [visNetworkMinJsBase64]",
  );
  buffer.writeln(
    "/// is only needed when generating an --offline HTML report.",
  );
  buffer.writeln("String get visNetworkMinJs =>");
  buffer.writeln(
    "    _cachedVisNetworkMinJs ??= utf8.decode(base64Decode(visNetworkMinJsBase64));",
  );
  buffer.writeln();
  buffer.writeln("String? _cachedVisNetworkMinJs;");

  final outputFile = File('lib/src/assets/vis_network_asset.dart');
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(buffer.toString());

  print(
    'Successfully generated ${outputFile.path} (${outputFile.lengthSync()} bytes)',
  );
}
