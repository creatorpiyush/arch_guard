import 'dart:convert';
import 'dart:io';

import 'package:arch_guard/src/cli/mcp_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _sample = 'example/cases/sample_project';

void main() {
  var nextId = 0;

  /// Sends one request to [server] and returns the decoded response.
  Future<Map<String, dynamic>> send(
    McpServer server,
    String method, [
    Map<String, Object?>? params,
  ]) async {
    final line = await server.handle(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': ++nextId,
        'method': method,
        'params': ?params,
      }),
    );
    return jsonDecode(line!) as Map<String, dynamic>;
  }

  /// Calls [tool] and returns its text, failing on any error.
  Future<String> call(
    McpServer server,
    String tool, [
    Map<String, Object?> args = const {},
  ]) async {
    final r = await send(server, 'tools/call', {
      'name': tool,
      'arguments': args,
    });
    expect(r['error'], isNull, reason: '$r');
    expect(r['result']['isError'], isFalse, reason: '$r');
    return r['result']['content'][0]['text'] as String;
  }

  Future<Map<String, dynamic>> callJson(
    McpServer server,
    String tool, [
    Map<String, Object?> args = const {},
  ]) async =>
      jsonDecode(await call(server, tool, args)) as Map<String, dynamic>;

  group('protocol', () {
    final server = McpServer(p.canonicalize(_sample));

    test(
      'initialize echoes a supported version and names the server',
      () async {
        final r = await send(server, 'initialize', {
          'protocolVersion': '2025-03-26',
          'capabilities': {},
          'clientInfo': {'name': 'test', 'version': '0'},
        });
        expect(r['result']['protocolVersion'], '2025-03-26');
        expect(r['result']['capabilities'], {'tools': {}});
        expect(r['result']['serverInfo']['name'], 'arch_guard');

        final unknown = await send(server, 'initialize', {
          'protocolVersion': '1999-01-01',
        });
        expect(unknown['result']['protocolVersion'], '2025-06-18');
      },
    );

    test('tools/list names every tool with an object schema', () async {
      final r = await send(server, 'tools/list');
      final tools = r['result']['tools'] as List;
      expect(tools.map((t) => t['name']), [
        'check',
        'check_import',
        'layer_of',
        'why',
        'affected',
        'explain',
      ]);
      for (final t in tools) {
        expect(t['description'], isNotEmpty);
        expect(t['inputSchema']['type'], 'object');
      }
    });

    test('notifications get no response', () async {
      expect(
        await server.handle(
          '{"jsonrpc":"2.0","method":"notifications/initialized"}',
        ),
        isNull,
      );
      expect(await server.handle(''), isNull);
    });

    test(
      'bad input gives JSON-RPC errors and the server keeps going',
      () async {
        Future<int> code(String line) async =>
            (jsonDecode((await server.handle(line))!)['error']['code']) as int;

        expect(await code('not json'), -32700);
        expect(await code('[1, 2]'), -32600);
        expect(await code('{"jsonrpc":"2.0","id":1}'), -32600);
        expect(await code('{"jsonrpc":"2.0","id":1,"method":"nope"}'), -32601);
        expect(
          (await send(server, 'tools/call', {'name': 'nope'}))['error']['code'],
          -32602,
        );
        expect(
          (await send(server, 'tools/call', {
            'name': 'layer_of',
            'arguments': {},
          }))['error']['code'],
          -32602,
        );
        expect(
          (await send(server, 'tools/call', {
            'name': 'layer_of',
            'arguments': {'file': 'lib/a.dart', 'extra': 1},
          }))['error']['code'],
          -32602,
        );
        // Still answers after all of that.
        expect((await send(server, 'ping'))['result'], {});
      },
    );

    test('a tool that fails returns isError, not a protocol error', () async {
      final r = await send(server, 'tools/call', {
        'name': 'why',
        'arguments': {'from': 'lib/nope.dart', 'to': 'dart:io'},
      });
      expect(r['result']['isError'], isTrue);
      expect(r['result']['content'][0]['text'], startsWith('Error: '));
    });
  });

  group('tools on sample_project', () {
    final server = McpServer(p.canonicalize(_sample));

    test(
      'check lists the CLI failures and report-only layer violations',
      () async {
        final r = await callJson(server, 'check');
        expect(r['passed'], isFalse);
        expect(r['failures'], [
          'Circular dependency: lib/widgets/nav.dart -> lib/screens/home.dart '
              '-> lib/widgets/nav.dart',
          'Circular dependency: lib/services/session_service.dart -> '
              'lib/services/auth_service.dart -> lib/models/user.dart -> '
              'lib/services/session_service.dart',
        ]);
        // fail_on_layer_violation: false, so the CLI prints it but exits 0
        // with --no-fail-on-cycle.
        expect(r['reportOnly'], [
          allOf(
            startsWith('Layer violation: lib/models/user.dart:'),
            contains('(models) imports lib/services/session_service.dart'),
          ),
        ]);
      },
    );

    test('check_import: a layer the file may not import', () async {
      final r = await callJson(server, 'check_import', {
        'file': 'lib/models/account.dart',
        'import': 'package:sample_project/services/auth_service.dart',
      });
      expect(r['allowed'], isFalse);
      expect(r['resolvesTo'], 'lib/services/auth_service.dart');
      expect(r['violations'], [
        {
          'kind': 'layer',
          'rule': contains('models'),
          'suggestion': contains('allowed_imports'),
        },
      ]);
    });

    test('check_import: allowed relative import and dart: library', () async {
      final relative = await callJson(server, 'check_import', {
        'file': 'lib/screens/settings.dart',
        'import': '../services/auth_service.dart',
      });
      expect(relative['allowed'], isTrue);
      expect(relative['resolvesTo'], 'lib/services/auth_service.dart');

      final sdk = await callJson(server, 'check_import', {
        'file': 'lib/models/user.dart',
        'import': 'dart:io',
      });
      expect(sdk, containsPair('allowed', true));
      expect(sdk.containsKey('resolvesTo'), isFalse);
    });

    test('layer_of: a layered file and an unlayered one', () async {
      final r = await callJson(server, 'layer_of', {
        'file': 'lib/services/new_service.dart',
      });
      expect(r['layer'], {
        'name': 'services',
        'allowedImports': ['services', 'models'],
        'forbiddenPackages': <String>[],
      });
      expect(r['module'], isNull);

      final none = await callJson(server, 'layer_of', {
        'file': 'lib/main.dart',
      });
      expect(none['layer'], isNull);
    });

    test('why matches the CLI path', () async {
      final r = await callJson(server, 'why', {
        'from': 'lib/main.dart',
        'to': 'dart:convert',
      });
      expect(r['found'], isTrue);
      expect(r['steps'], [
        {
          'from': 'lib/main.dart',
          'to': 'lib/services/auth_service.dart',
          'type': 'import',
          'line': 2,
        },
        {
          'from': 'lib/services/auth_service.dart',
          'to': 'lib/models/user.dart',
          'type': 'import',
          'line': 1,
        },
        {
          'from': 'lib/models/user.dart',
          'to': 'dart:convert',
          'type': 'import',
          'line': 2,
        },
      ]);
    });

    test('explain matches the CLI --explain text', () async {
      final text = await call(server, 'explain', {
        'file': 'lib/models/user.dart',
      });
      final cli = Process.runSync(Platform.resolvedExecutable, [
        'bin/arch_guard.dart',
        _sample,
        '--no-color',
        '--explain',
        'lib/models/user.dart',
      ]);
      expect(cli.stdout, text);
    });
  });

  group('forbidden packages, modules and affected', () {
    late Directory project;
    late McpServer server;

    void write(String path, String content) {
      final f = File(p.join(project.path, path));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    void git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: project.path);
      if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
    }

    setUp(() {
      project = Directory.systemTemp.createTempSync('arch_guard_mcp_');
      write('pubspec.yaml', 'name: app\n');
      write('arch_guard.yaml', '''
forbidden_packages:
  - http
modules:
  roots:
    - lib/features/*
  public:
    - api.dart
''');
      write('lib/features/cart/api.dart', '');
      write('lib/features/cart/src/store.dart', '');
      write('lib/features/home/home.dart', '');
      write(
        'test/home_test.dart',
        "import 'package:app/features/home/home.dart';\n",
      );
      server = McpServer(p.canonicalize(project.path));
    });

    tearDown(() => project.deleteSync(recursive: true));

    test('check_import: forbidden package', () async {
      final r = await callJson(server, 'check_import', {
        'file': 'lib/features/home/home.dart',
        'import': 'package:http/http.dart',
      });
      expect(r['allowed'], isFalse);
      expect(r['violations'], [containsPair('kind', 'forbidden_package')]);
    });

    test('check_import: module private file vs public api', () async {
      final private = await callJson(server, 'check_import', {
        'file': 'lib/features/home/home.dart',
        'import': 'package:app/features/cart/src/store.dart',
      });
      expect(private['violations'], [containsPair('kind', 'module')]);

      final public = await callJson(server, 'check_import', {
        'file': 'lib/features/home/home.dart',
        'import': '../cart/api.dart',
      });
      expect(public['allowed'], isTrue);
    });

    test('layer_of reports the module', () async {
      final r = await callJson(server, 'layer_of', {
        'file': 'lib/features/cart/src/store.dart',
      });
      expect(r['module'], {
        'name': 'cart',
        'dir': 'lib/features/cart',
        'publicFiles': ['api.dart'],
      });
      expect(r['forbiddenPackages'], ['http']);
    });

    test('affected matches affected --json', () async {
      git(['init', '-q', '-b', 'main']);
      git(['config', 'user.email', 't@example.com']);
      git(['config', 'user.name', 'T']);
      git(['add', '.']);
      git(['commit', '-qm', 'base']);
      write('lib/features/home/home.dart', '// changed\n');

      final r = await callJson(server, 'affected', {'since': 'main'});
      expect(r['tests'], ['test/home_test.dart']);
      final cli = Process.runSync(Platform.resolvedExecutable, [
        'bin/arch_guard.dart',
        'affected',
        project.path,
        '--since',
        'main',
        '--json',
      ]);
      expect(jsonDecode(cli.stdout as String), r);
    });

    test('affected with a bad ref is a tool error', () async {
      git(['init', '-q', '-b', 'main']);
      final r = await send(server, 'tools/call', {
        'name': 'affected',
        'arguments': {'since': 'no-such-ref'},
      });
      expect(r['result']['isError'], isTrue);
    });
  });

  test('arch_guard mcp prints only JSON-RPC on stdout', () async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'bin/arch_guard.dart',
      'mcp',
      _sample,
    ]);
    process.stdin
      ..writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-06-18',
            'capabilities': {},
            'clientInfo': {'name': 'test', 'version': '0'},
          },
        }),
      )
      ..writeln('{"jsonrpc":"2.0","method":"notifications/initialized"}')
      ..writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {'name': 'check', 'arguments': {}},
        }),
      );
    await process.stdin.close();
    final lines = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
    expect(await process.exitCode, 0);
    expect(lines, hasLength(2));
    for (final line in lines) {
      expect(jsonDecode(line), containsPair('jsonrpc', '2.0'));
    }
    expect(jsonDecode(lines[1])['id'], 2);
  });
}
