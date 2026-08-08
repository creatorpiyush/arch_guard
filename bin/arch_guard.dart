import 'dart:io';
import 'package:arch_guard/src/cli/run.dart';

Future<void> main(List<String> args) async {
  final exitCode = await runCli(args);
  if (exitCode != 0) {
    exit(exitCode);
  }
}
