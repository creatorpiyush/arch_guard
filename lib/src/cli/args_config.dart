import 'package:args/args.dart';

/// Configures the command line argument parser for dep_graph_visualizer.
class ArgsConfig {
  static ArgParser buildParser() {
    final parser = ArgParser();

    parser.addMultiOption(
      'format',
      abbr: 'f',
      allowed: ['text', 'dot', 'html', 'all'],
      defaultsTo: ['text'],
      help: 'Export format(s) to generate (text, dot, html, or all).',
    );

    parser.addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'dep_graph_output',
      help: 'Output directory for generated dot/html files.',
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
