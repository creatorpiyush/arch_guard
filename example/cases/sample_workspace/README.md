# Sample workspace (library API)

A Dart workspace whose two packages import each other: a cycle across packages. [`example.dart`](../../example.dart) scans it with workspace discovery and checks `workspace_rules`. For workspace rules through the CLI, see [workspace_rules](../workspace_rules/README.md).

```bash
dart run arch_guard example/cases/sample_workspace
```
