import 'package:args/args.dart';

/// Configures the command line argument parser for arch_guard.
class ArgsConfig {
  static ArgParser buildParser() {
    final parser = ArgParser();

    parser.addMultiOption(
      'format',
      abbr: 'f',
      allowed: ['text', 'dot', 'html', 'json', 'mermaid', 'all'],
      defaultsTo: ['text'],
      help:
          'Export format(s) to generate (text, dot, html, json, mermaid, or all).',
    );

    parser.addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'arch_guard_output',
      help: 'Output directory for generated dot/html/json/mermaid files.',
    );

    parser.addOption(
      'scope',
      allowed: ['cycles', 'all'],
      defaultsTo: 'cycles',
      help:
          'Export graph scope: cycles (SCCs only + 1-hop context) or all (entire graph).',
    );

    parser.addOption(
      'explain',
      help:
          'File path to explain incoming/outgoing dependencies and SCC membership.',
    );

    parser.addMultiOption(
      'scan-dir',
      defaultsTo: ['lib'],
      help: 'Subdirectory/subdirectories within project root to scan.',
    );

    parser.addMultiOption(
      'exclude',
      help: 'Custom glob pattern(s) to exclude from scanning.',
    );

    parser.addFlag(
      'color',
      defaultsTo: true,
      negatable: true,
      help: 'Enable ANSI colored output in terminal.',
    );

    parser.addFlag(
      'offline',
      defaultsTo: false,
      negatable: true,
      help:
          'Inline static assets in HTML report for air-gapped CI environments.',
    );

    parser.addFlag(
      'fail-on-cycle',
      defaultsTo: true,
      negatable: true,
      help: 'Return exit code 1 if circular dependencies are found.',
    );

    parser.addFlag(
      'workspace',
      defaultsTo: true,
      negatable: true,
      help:
          'Auto-discover and scan member packages in a Dart 3.6+ workspace or monorepo.',
    );

    parser.addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage help message.',
    );

    return parser;
  }
}
