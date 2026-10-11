# Sample project (library API)

A small app with two cycles, a layer violation and a `dart:convert` import. [`example.dart`](../../example.dart) runs the library API against it, covering:

- scanning, cycles and hints
- layers and the explainer
- `ArchAnalysis.run()`
- forbidden packages and metrics
- layer coverage and baselines
- every exporter

```bash
dart run example/example.dart                        # library API walkthrough
dart run arch_guard example/cases/sample_project     # the same project through the CLI
```
