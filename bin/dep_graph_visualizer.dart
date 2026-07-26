import 'dart:io';
import 'package:dep_graph_visualizer/src/cli/run.dart';

Future<void> main(List<String> args) async {
  final exitCode = await runCli(args);
  if (exitCode != 0) {
    exit(exitCode);
  }
}
