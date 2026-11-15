import 'dart:io';
import 'package:args/args.dart';

import '../version.dart';
import 'affected_command.dart';
import 'analyze_command.dart';
import 'args_config.dart';
import 'init_command.dart';
import 'why_command.dart';

/// Subcommands: the usage line under `arch_guard --help`, the usage line and
/// description under `arch_guard <name> --help`, and the runner. Each name
/// also needs a parser in [ArgsConfig.buildParser].
final _subcommands =
    <
      String,
      ({
        String summary,
        String usage,
        String about,
        Future<int> Function(ArgResults) run,
      })
    >{
      'init': (
        summary: 'init [project_path] [--preset <name>]',
        usage: 'init [project_path] [options]',
        about:
            'Detects the project layout and writes a starter arch_guard.yaml.',
        run: runInit,
      ),
      'affected': (
        summary: 'affected [project_path] --since <ref>',
        usage: 'affected [project_path] --since <git-ref> [options]',
        about:
            'Lists the tests (or files, or packages) that changes since a git '
            'ref can affect.',
        run: runAffected,
      ),
      'why': (
        summary: 'why <from> <to> [project_path]',
        usage: 'why <from> <to> [project_path] [options]',
        about:
            'Prints the shortest import path from a file or folder to a file, '
            'folder or package (package:flutter, dart:io). Exits 1 when there '
            'is none.',
        run: runWhy,
      ),
    };

/// Entry point logic for CLI execution.
Future<int> runCli(List<String> args) async {
  final parser = ArgsConfig.buildParser();

  ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    final sub = args.isEmpty ? null : parser.commands[args.first];
    stderr.writeln((sub ?? parser).usage);
    return 64; // Sysexit code for command-line usage error
  }

  final command = argResults.command;
  if (command != null) {
    if (argResults['watch'] == true) {
      stderr.writeln('Error: --watch cannot be combined with ${command.name}.');
      return 64;
    }
    final sub = _subcommands[command.name]!;
    if (command['help'] == true) {
      stdout.writeln('Usage: arch_guard ${sub.usage}');
      stdout.writeln();
      stdout.writeln(sub.about);
      stdout.writeln();
      stdout.writeln(parser.commands[command.name]!.usage);
      return 0;
    }
    return sub.run(command);
  }

  if (argResults['help'] == true) {
    stdout.writeln('Usage: arch_guard [project_path] [options]');
    for (final sub in _subcommands.values) {
      stdout.writeln('       arch_guard ${sub.summary}');
    }
    stdout.writeln();
    stdout.writeln(parser.usage);
    return 0;
  }

  if (argResults['version'] == true) {
    stdout.writeln('arch_guard $packageVersion');
    return 0;
  }

  return runAnalyze(argResults, args);
}
