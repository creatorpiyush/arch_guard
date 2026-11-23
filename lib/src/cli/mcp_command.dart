import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../analysis/arch_analysis.dart';
import '../checker/layer_validator.dart';
import '../checker/module_validator.dart';
import '../checker/package_validator.dart';
import '../checker/workspace_validator.dart';
import '../graph/dependency_explainer.dart';
import '../graph/import_path.dart';
import '../models/scan_result.dart';
import '../scanner/git_changes.dart';
import '../scanner/import_reader.dart';
import '../version.dart';
import 'affected_command.dart';

/// Runs `arch_guard mcp [project_path]`: a Model Context Protocol server on
/// stdin/stdout. Returns `0` when stdin closes.
Future<int> runMcp(ArgResults args) async {
  final projectPath = args.rest.isNotEmpty ? args.rest.first : '.';
  final absProjectPath = p.canonicalize(projectPath);
  if (!Directory(absProjectPath).existsSync()) {
    stderr.writeln(
      'Error: Project directory "$absProjectPath" does not exist.',
    );
    return 2;
  }
  final server = McpServer(
    absProjectPath,
    scanDirs: args['scan-dir'] as List<String>,
    exclude: args['exclude'] as List<String>,
    enableWorkspace: args['workspace'] as bool,
  );
  // One request at a time, so responses keep the order of requests.
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final response = await server.handle(line);
    if (response != null) stdout.writeln(response);
  }
  return 0;
}

/// Thrown by a tool for a bad `arguments` object: a JSON-RPC
/// "Invalid params" error.
class _InvalidParams implements Exception {
  final String message;
  _InvalidParams(this.message);
}

/// The MCP server behind `arch_guard mcp`, one JSON-RPC message per line.
///
/// Every tool call scans the project again, so answers stay correct while
/// an agent edits files.
// ponytail: rescans per call (about 0.4 s for 5,000 files); cache the
// analysis keyed on file stamps if agents find it slow.
class McpServer {
  /// The project root.
  final String root;

  /// Folders under [root] (and each workspace member) to scan.
  final List<String> scanDirs;

  /// Extra exclude globs.
  final List<String> exclude;

  /// Whether to scan workspace members.
  final bool enableWorkspace;

  /// Creates a server for the project at [root].
  McpServer(
    this.root, {
    this.scanDirs = const ['lib'],
    this.exclude = const [],
    this.enableWorkspace = true,
  });

  // Newest first. Tools-only servers behave the same in all three.
  static const _supportedVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];

  static const _file = {
    'type': 'string',
    'description': 'Project-relative path, e.g. lib/ui/home.dart.',
  };

  static const _since = {
    'type': 'string',
    'description':
        'Git ref, e.g. origin/main. Compares with the merge base, plus '
        'uncommitted and untracked files.',
  };

  static Map<String, Object> _schema(
    Map<String, Object> properties, [
    List<String> required = const [],
  ]) => {
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  };

  /// The tools, as `tools/list` returns them.
  static final tools = [
    {
      'name': 'check',
      'description':
          'Runs every arch_guard rule (cycles, layers, forbidden packages, '
          'modules, workspace, metrics, unused files) like the CLI. Returns '
          'the problems that fail the run and config warnings. Problems '
          'already in the baseline are not listed.',
      'inputSchema': _schema({
        'since': {
          ..._since,
          'description':
              'Only report problems touching files changed since this git '
              'ref, e.g. origin/main.',
        },
      }),
    },
    {
      'name': 'check_import',
      'description':
          'Asks whether a file may import a URI, before writing the import. '
          'Returns allowed, or each rule the import would break with a fix '
          'suggestion. The file need not exist yet.',
      'inputSchema': _schema(
        {
          'file': _file,
          'import': {
            'type': 'string',
            'description':
                'The URI as written in the import, e.g. '
                'package:app/data/repo.dart, ../models/user.dart or dart:io.',
          },
        },
        ['file', 'import'],
      ),
    },
    {
      'name': 'layer_of',
      'description':
          'The layer, module and workspace package of a file, and what it '
          'may import. The file need not exist yet.',
      'inputSchema': _schema({'file': _file}, ['file']),
    },
    {
      'name': 'why',
      'description':
          'The shortest import path from a file or folder to a file, folder '
          'or package (package:flutter, dart:io).',
      'inputSchema': _schema(
        {
          'from': {'type': 'string', 'description': 'File or folder.'},
          'to': {
            'type': 'string',
            'description': 'File, folder, or package such as package:http.',
          },
        },
        ['from', 'to'],
      ),
    },
    {
      'name': 'affected',
      'description':
          'Files, tests and workspace packages that the changes since a git '
          'ref can affect: the tests to run.',
      'inputSchema': _schema({'since': _since}, ['since']),
    },
    {
      'name': 'explain',
      'description':
          'What a file imports, what imports it, and the import cycle it is '
          'in, if any.',
      'inputSchema': _schema({'file': _file}, ['file']),
    },
  ];

  /// Handles one line of input. Returns the response line, or `null` for a
  /// notification.
  Future<String?> handle(String line) async {
    if (line.trim().isEmpty) return null;
    Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException catch (e) {
      return _error(null, -32700, 'Parse error: ${e.message}');
    }
    if (message is! Map ||
        message['jsonrpc'] != '2.0' ||
        message['method'] is! String) {
      final id = message is Map ? message['id'] : null;
      return _error(id, -32600, 'Invalid Request');
    }
    final id = message['id'];
    final method = message['method'] as String;
    final params = message['params'];
    // Notifications (no id) get no response, whatever the method.
    if (!message.containsKey('id')) return null;

    switch (method) {
      case 'initialize':
        final requested = params is Map ? params['protocolVersion'] : null;
        return _result(id, {
          'protocolVersion': _supportedVersions.contains(requested)
              ? requested!
              : _supportedVersions.first,
          'capabilities': {'tools': <String, Object>{}},
          'serverInfo': {'name': 'arch_guard', 'version': packageVersion},
        });
      case 'ping':
        return _result(id, <String, Object>{});
      case 'tools/list':
        return _result(id, {'tools': tools});
      case 'tools/call':
        if (params is! Map || params['name'] is! String) {
          return _error(id, -32602, 'tools/call needs a "name".');
        }
        final arguments = params['arguments'] ?? <String, Object?>{};
        if (arguments is! Map) {
          return _error(id, -32602, '"arguments" must be an object.');
        }
        try {
          final text = await call(
            params['name'] as String,
            arguments.cast<String, Object?>(),
          );
          return _result(id, {
            'content': [
              {'type': 'text', 'text': text},
            ],
            'isError': false,
          });
        } on _InvalidParams catch (e) {
          return _error(id, -32602, e.message);
        } on Exception catch (e) {
          // A tool that ran but failed (bad config, git error, no match):
          // a result the agent can read, not a protocol error.
          final message = switch (e) {
            FormatException(:final message) => message,
            GitException(:final message) => message,
            _ => '$e',
          };
          return _result(id, {
            'content': [
              {'type': 'text', 'text': 'Error: $message'},
            ],
            'isError': true,
          });
        }
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  /// Runs tool [name] with [args] and returns its text (JSON for every tool
  /// but `explain`).
  Future<String> call(String name, Map<String, Object?> args) async {
    final tool = tools.where((t) => t['name'] == name).firstOrNull;
    if (tool == null) throw _InvalidParams('Unknown tool: $name');
    final schema = tool['inputSchema'] as Map<String, Object>;
    final known = (schema['properties'] as Map).keys.toSet();
    for (final key in args.keys) {
      if (!known.contains(key)) {
        throw _InvalidParams('$name: unknown argument "$key".');
      }
    }
    String arg(String key) {
      final value = args[key];
      if (value is! String || value.isEmpty) {
        throw _InvalidParams('$name needs "$key" (a non-empty string).');
      }
      return value;
    }

    String? optional(String key) => args[key] == null ? null : arg(key);

    const json = JsonEncoder.withIndent('  ');
    switch (name) {
      case 'check':
        final analysis = await _analyse(since: optional('since'));
        final failures = analysis.failures();
        final config = analysis.config;
        String at(String file, int? line) =>
            line == null ? file : '$file:$line';
        return json.convert({
          'passed': failures.isEmpty,
          'failures': failures,
          // Printed by the CLI but not failing the run under this config.
          'reportOnly': [
            if (!config.failOnLayerViolation)
              for (final v in analysis.newLayerViolations)
                'Layer violation: ${at(v.sourceFile, v.line)} '
                    '(${v.sourceLayer}) imports ${v.targetFile} '
                    '(${v.targetLayer}). ${v.rule}',
            if (!config.failOnUnusedFiles)
              for (final f in analysis.newUnusedFiles)
                'Unused file: $f (no entry point reaches it).',
            if (!config.failOnDependencyProblems)
              for (final d in analysis.newDependencyProblems)
                'Dependency: ${d.rule}',
          ],
          'warnings': [...analysis.config.warnings, ...analysis.warnings],
          'since': ?analysis.since,
        });
      case 'check_import':
        return json.convert(
          checkImport(await _analyse(), _relative(arg('file')), arg('import')),
        );
      case 'layer_of':
        return json.convert(layerOf(await _analyse(), _relative(arg('file'))));
      case 'why':
        final from = arg('from');
        final to = arg('to');
        final scan = (await _analyse()).scan;
        final Set<String> files;
        final PathTarget target;
        try {
          files = ImportPath.matchFiles(scan, from);
          target = ImportPath.matchTarget(scan, to);
        } on ArgumentError catch (e) {
          throw FormatException('${e.message}');
        }
        final path = ImportPath.find(result: scan, from: files, to: target);
        return json.convert({
          'from': from.replaceAll('\\', '/'),
          'to': target.label,
          'found': path != null,
          'steps': [
            for (final s in path ?? const <ImportStep>[])
              {
                'from': s.from,
                'to': s.to,
                'type': s.type,
                'line': ?s.line,
                'condition': ?s.condition,
              },
          ],
        });
      case 'affected':
        final since = arg('since');
        final (changed, result) = await findAffected(
          root,
          since,
          exclude: exclude,
          enableWorkspace: enableWorkspace,
        );
        return json.convert(affectedJson(since, changed, result));
      case 'explain':
        final analysis = await _analyse();
        return DependencyExplainer.explainFile(
          targetFile: arg('file'),
          graph: analysis.graph,
          cycles: analysis.cycles,
          color: false,
        );
    }
    throw StateError('unreachable: $name');
  }

  Future<ArchAnalysis> _analyse({String? since}) => ArchAnalysis.run(
    projectPath: root,
    scanDirs: scanDirs,
    exclude: exclude,
    enableWorkspace: enableWorkspace,
    since: since,
  );

  /// [file] relative to [root] with `/` separators.
  String _relative(String file) {
    final rel = p.isAbsolute(file) ? p.relative(file, from: root) : file;
    return p.posix.normalize(rel.replaceAll('\\', '/'));
  }

  /// Whether [file] may import [uri] under the rules of [analysis].
  static Map<String, Object?> checkImport(
    ArchAnalysis analysis,
    String file,
    String uri,
  ) {
    final config = analysis.config;
    final scan = analysis.scan;
    final memberOf = WorkspaceValidator.memberResolver(scan.packages);
    final ownPackage = memberOf(file)?.name ?? scan.packageName;
    final violations = <Map<String, String>>[];
    void add(String kind, String rule, String suggestion) =>
        violations.add({'kind': kind, 'rule': rule, 'suggestion': suggestion});

    // As the scanner does: a package other than the file's own is checked
    // against forbidden_packages, and a URI inside the project is an edge.
    final package = PackageImport.packageOf(uri);
    if (package != null && package != ownPackage) {
      final v = PackageValidator.checker(config)(file, uri);
      if (v != null) add('forbidden_package', v.rule, v.suggestion);
    }
    final target = ImportReader.resolveUri(
      uri: uri,
      packageName: ownPackage,
      importingFileRelativePath: file,
      workspacePackages: scan.packages.isEmpty
          ? null
          : {for (final m in scan.packages) m.name: m.libPath},
    );
    if (target != null) {
      // ponytail: checks the direct import only; a barrel that re-exports
      // another layer is caught by `check` once the import is written.
      final layer = LayerValidator.checker(config)(file, target);
      if (layer != null) add('layer', layer.rule, layer.suggestion);
      final module = ModuleValidator.checker(config)(file, target);
      if (module != null) add('module', module.rule, module.suggestion);
      if (scan.packages.isNotEmpty) {
        final ws = WorkspaceValidator.checker(config, memberOf)(file, target);
        if (ws != null) add('workspace', ws.rule, ws.suggestion);
      }
    }
    return {
      'file': file,
      'import': uri,
      'resolvesTo': ?target,
      'allowed': violations.isEmpty,
      'violations': violations,
    };
  }

  /// The layer, module and workspace package of [file] under [analysis].
  static Map<String, Object?> layerOf(ArchAnalysis analysis, String file) {
    final config = analysis.config;
    final layer = config.layers[LayerValidator.layerResolver(config)(file)];
    final module = ModuleValidator.moduleResolver(config)(file);
    final packages = analysis.scan.packages;
    final member = packages.isEmpty
        ? null
        : WorkspaceValidator.memberResolver(packages)(file);
    return {
      'file': file,
      'layer': layer == null
          ? null
          : {
              'name': layer.name,
              'allowedImports': layer.allowedImports,
              'forbiddenPackages': layer.forbiddenPackages,
            },
      'forbiddenPackages': config.forbiddenPackages,
      'module': module == null
          ? null
          : {
              'name': module.name,
              'dir': module.dir,
              'allowedModules': ?config.modules?.allowed[module.name],
              'publicFiles': config.modules?.public,
            },
      'workspacePackage': member?.name,
    };
  }

  static String _result(Object? id, Object result) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result});

  static String _error(Object? id, int code, String message) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });
}
