import 'package:args/args.dart';

import '../models/layer_presets.dart';

/// Configures the command line argument parser for arch_guard.
class ArgsConfig {
  /// Builds the parser with every arch_guard option and flag.
  static ArgParser buildParser() {
    final parser = ArgParser();

    parser.addMultiOption(
      'format',
      abbr: 'f',
      allowed: [
        'text',
        'dot',
        'html',
        'json',
        'mermaid',
        'sarif',
        'markdown',
        'all',
      ],
      defaultsTo: ['text'],
      help:
          'Export format(s) to generate (text, dot, html, json, mermaid, '
          'sarif, markdown, or all).',
    );

    parser.addOption(
      'output',
      abbr: 'o',
      defaultsTo: 'arch_guard_output',
      help: 'Output directory for generated report files.',
    );

    parser.addOption(
      'baseline',
      defaultsTo: 'arch_guard_baseline.json',
      help:
          'Baseline file of known problems (relative to the project). When it '
          'exists, only problems not listed in it fail the run.',
    );

    parser.addFlag(
      'update-baseline',
      negatable: false,
      help:
          'Write the current cycles and layer violations to the baseline file '
          'and exit with code 0.',
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

    parser.addOption(
      'since',
      valueHelp: 'git-ref',
      help:
          'Only report problems touching files changed since the merge base '
          'with this ref (plus uncommitted and untracked files), e.g. '
          'origin/main. The whole project is still analysed.',
    );

    parser.addFlag(
      'watch',
      negatable: false,
      help:
          'Re-run when Dart files, the config or the baseline change. '
          'Stop with Ctrl+C.',
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

    parser.addFlag(
      'version',
      negatable: false,
      help: 'Print the arch_guard version.',
    );

    parser.addCommand('init', buildInitParser());
    parser.addCommand('affected', buildAffectedParser());
    parser.addCommand('why', buildWhyParser());

    return parser;
  }

  /// Parser for `arch_guard init [project_path]`.
  static ArgParser buildInitParser() {
    return ArgParser()
      ..addOption(
        'preset',
        allowed: ['auto', 'none', ...LayerPresets.names],
        defaultsTo: 'auto',
        help: 'Layer preset to use; `auto` detects it from the folder layout.',
        allowedHelp: {
          'auto': 'Detect from folders and dependencies.',
          'none': 'Write a commented template without a preset.',
          ...LayerPresets.descriptions,
        },
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite an existing arch_guard.yaml.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the configuration instead of writing it.',
      )
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Print init usage.');
  }

  /// Parser for `arch_guard affected [project_path] --since <ref>`.
  static ArgParser buildAffectedParser() {
    return ArgParser()
      ..addOption(
        'since',
        valueHelp: 'git-ref',
        help:
            'Required. Files changed since the merge base with this ref '
            '(plus uncommitted and untracked files), e.g. origin/main.',
      )
      ..addOption(
        'print',
        allowed: ['tests', 'files', 'packages'],
        defaultsTo: 'tests',
        help: 'What to list, one per line.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print every list as JSON instead.',
      )
      ..addMultiOption(
        'exclude',
        help: 'Custom glob pattern(s) to exclude from scanning.',
      )
      ..addFlag(
        'workspace',
        defaultsTo: true,
        help: 'Auto-discover and scan workspace member packages.',
      )
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Print affected usage.',
      );
  }

  /// Parser for `arch_guard why <from> <to> [project_path]`.
  static ArgParser buildWhyParser() {
    return ArgParser()
      ..addMultiOption(
        'scan-dir',
        defaultsTo: ['lib'],
        help: 'Subdirectory/subdirectories within project root to scan.',
      )
      ..addMultiOption(
        'exclude',
        help: 'Custom glob pattern(s) to exclude from scanning.',
      )
      ..addFlag(
        'workspace',
        defaultsTo: true,
        help: 'Auto-discover and scan workspace member packages.',
      )
      ..addFlag(
        'color',
        defaultsTo: true,
        help: 'Enable ANSI colored output in terminal.',
      )
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Print why usage.');
  }
}
