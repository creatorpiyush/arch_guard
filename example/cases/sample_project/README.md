# Sample project (library API)

A small app with two cycles, a layer violation and a `dart:convert` import. [`example.dart`](../../example.dart) runs the library API against it: scanning, cycles and hints, layers, `--explain`, `ArchAnalysis.run()`, forbidden packages and metrics.

```bash
dart run example/example.dart                        # library API walkthrough
dart run arch_guard example/cases/sample_project     # the same project through the CLI
```
